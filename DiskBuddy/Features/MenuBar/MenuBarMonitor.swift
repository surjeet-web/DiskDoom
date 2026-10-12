import Foundation
import SwiftUI
import UserNotifications

// MARK: - Feature 6: Menu bar monitor — background disk polling + display state
//
// Polls volume capacity every 60s (URLResourceValues, zero file walking).
// Quick-folder sizes (Downloads/Trash) are measured OFF-MAIN, LAZILY (only when
// the panel is actually shown), behind a TTL and a hard time/entry budget —
// they used to be walked in full every 60 s forever, which after one big cleanup
// meant re-walking a `~/.Trash` holding hundreds of thousands of files.
// Space hogs are refreshed from real scan results via updateFromScan(_:).

@MainActor
final class MenuBarMonitor: ObservableObject {
    // Current disk state
    @Published private(set) var freeSpace: Int64 = 0
    @Published private(set) var usedSpace: Int64 = 0
    @Published private(set) var totalCapacity: Int64 = 0
    @Published private(set) var freePercent: Double = 0
    @Published private(set) var usedPercent: Double = 0

    // Display
    @Published private(set) var statusText = "—"
    @Published private(set) var menuBarTitle = "—"
    @Published private(set) var spaceState: SpaceState = .unknown
    @Published private(set) var lastUpdated: Date?

    // Quick stats. Exposed as computed accessors that kick off a lazy, TTL-cached,
    // off-main measurement — so the walk happens because somebody *read* the
    // figure (i.e. the panel is on screen), not because a timer fired.
    @Published private var cachedDownloadsBytes: Int64 = -1 // -1 = measuring
    @Published private var cachedTrashBytes: Int64 = -1

    var downloadsBytes: Int64 {
        refreshQuickFolderStats(force: false)
        return cachedDownloadsBytes
    }

    var trashBytes: Int64 {
        refreshQuickFolderStats(force: false)
        return cachedTrashBytes
    }

    private var quickFolderTask: Task<Void, Never>?
    private var quickFolderToken = ScanCancellation()
    private var lastQuickFolderMeasure: Date?

    /// How stale a Downloads/Trash size may get. Figures are only displayed
    /// inside the panel, so 2 minutes is imperceptible and costs ~1/30th of the
    /// previous walk rate.
    private static let quickFolderTTL: TimeInterval = 120
    /// Wall-clock budget for one quick-folder walk. A Trash with 300k files
    /// stops here rather than saturating the disk for a minute.
    private static let quickFolderBudget: TimeInterval = 4
    /// Entry cap for the same reason.
    private static let quickFolderMaxEntries = 150_000

    // From last scan
    @Published private(set) var topSpaceHogs: [SpaceHog] = []
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var litterScore: Int?
    @Published private(set) var healthGrade: String?

    private var notifications: NotificationService?
    private var pollTask: Task<Void, Never>?
    private var lastAlertedState: SpaceState = .unknown

    enum SpaceState: Int, Comparable {
        case unknown = -1
        case healthy = 0   // > warning threshold free (default 30%+ band)
        case okay = 1      // 15–30% free
        case low = 2       // below warning threshold
        case critical = 3  // below critical threshold
        case full = 4      // < 2% free

        static func < (l: SpaceState, r: SpaceState) -> Bool { l.rawValue < r.rawValue }

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .healthy: return .green
            case .okay: return .blue
            case .low: return .yellow
            case .critical: return .orange
            case .full: return .red
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "externaldrive"
            case .healthy, .okay: return "externaldrive.fill"
            case .low: return "externaldrive.fill.badge.exclamationmark"
            case .critical, .full: return "externaldrive.fill.badge.xmark"
            }
        }

        var notificationTitle: String? {
            switch self {
            case .low: return "Disk Space Running Low"
            case .critical: return "Disk Space Critically Low"
            case .full: return "Disk Almost Full"
            default: return nil
            }
        }
    }

    struct SpaceHog: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let size: Int64
        let icon: String

        var sizeFormatted: String { ByteFormatting.format(size) }
    }

    // MARK: - Lifecycle

    func startMonitoring(notifications: NotificationService) {
        self.notifications = notifications
        pollDiskSpace()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.pollDiskSpace()
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        quickFolderToken.cancel()
        quickFolderTask?.cancel()
        quickFolderTask = nil
    }

    // MARK: - Poll (main; capacity keys are cheap — no file walking)

    func pollDiskSpace() {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        guard total > 0 else { return }
        let used = total - free
        let freePct = Double(free) / Double(total) * 100

        // Configurable thresholds (Settings → Menu Bar).
        let defaults = UserDefaults.standard
        let warning = defaults.object(forKey: "warningThreshold") as? Double ?? 15
        let critical = defaults.object(forKey: "criticalThreshold") as? Double ?? 5

        let state: SpaceState
        switch freePct {
        case ..<2: state = .full
        case ..<critical: state = .critical
        case ..<warning: state = .low
        case ..<30: state = .okay
        default: state = .healthy
        }

        let previous = spaceState
        freeSpace = free
        usedSpace = used
        totalCapacity = total
        freePercent = freePct
        usedPercent = 100 - freePct
        spaceState = state
        menuBarTitle = Self.formatMenuBarTitle(free: free)
        statusText = "\(ByteFormatting.format(free)) free of \(ByteFormatting.format(total))"
        lastUpdated = Date()

        // Alert on degradation only (never on first sample, never twice for
        // the same state, never when alerts are disabled).
        let alertsEnabled = defaults.object(forKey: "lowSpaceAlerts") as? Bool ?? true
        if alertsEnabled, state > previous, previous != .unknown,
           state >= .low, state > lastAlertedState,
           let title = state.notificationTitle {
            lastAlertedState = state
            notifications?.sendDiskSpaceAlert(title: title, freeSpace: free, freePercent: freePct)
        }
        if state < lastAlertedState {
            lastAlertedState = state // recovery resets the alert ladder
        }

        // Nothing walks the disk here any more. `pollDiskSpace()` only reads cheap
        // volume capacity keys; the Downloads/Trash figures are produced lazily
        // by `downloadsBytes` / `trashBytes` when the panel reads them.
    }

    // MARK: - Quick folders (lazy, TTL-cached, bounded)

    /// Measure `~/Downloads` and `~/.Trash` off-main, bounded by a time budget
    /// and an entry cap, and cached for `quickFolderTTL`. Safe to call often:
    /// it is a no-op while a walk is in flight or the cache is fresh.
    func refreshQuickFolderStats(force: Bool) {
        if quickFolderTask != nil { return }
        if !force, let last = lastQuickFolderMeasure,
           Date().timeIntervalSince(last) < Self.quickFolderTTL { return }

        quickFolderToken.cancel()
        let token = ScanCancellation()
        quickFolderToken = token
        let deadline = Date().addingTimeInterval(Self.quickFolderBudget)
        quickFolderTask = Task { [weak self] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let result: (Int64, Int64) = await Task.detached {
                let downloads = Self.directoryBytes(
                    home.appendingPathComponent("Downloads"),
                    deadline: deadline, token: token)
                let trash = Self.directoryBytes(
                    home.appendingPathComponent(".Trash"),
                    deadline: deadline, token: token)
                return (downloads, trash)
            }.value
            guard let self, !token.isCancelled else { return }
            self.cachedDownloadsBytes = result.0
            self.cachedTrashBytes = result.1
            self.lastQuickFolderMeasure = Date()
            self.quickFolderTask = nil
        }
    }

    // MARK: - Update from scan results (real records + real inventory)

    func updateFromScan(records: [ScannedRecord], apps: [AppEntry], litterScore: Int?, healthGrade: String?) {
        var hogs: [SpaceHog] = []

        // Largest individual files (> 100 MB).
        let largeFiles = records
            .filter { !$0.isDirectory && $0.bytes > 100_000_000 }
            .sorted { $0.bytes > $1.bytes }
            .prefix(5)
        for file in largeFiles {
            hogs.append(SpaceHog(
                name: (file.path as NSString).lastPathComponent,
                path: file.path,
                size: file.bytes,
                icon: Self.icon(for: file.category)))
        }

        // Largest installed apps by total footprint.
        let topApps = apps
            .filter { !$0.isStale && $0.totalBytes > 0 }
            .sorted { $0.totalBytes > $1.totalBytes }
            .prefix(3)
        for app in topApps {
            hogs.append(SpaceHog(
                name: app.name,
                path: app.bundlePath,
                size: app.totalBytes,
                icon: "app.fill"))
        }

        hogs.sort { $0.size > $1.size }
        topSpaceHogs = Array(hogs.prefix(8))
        lastScanDate = Date()
        self.litterScore = litterScore
        self.healthGrade = healthGrade
    }

    // MARK: - Formatting

    /// Compact menu bar title: "45G", "4.2T", "890M".
    static func formatMenuBarTitle(free: Int64) -> String {
        let gib = Double(1_073_741_824)
        if Double(free) >= gib * 1024 {
            return String(format: "%.1fT", Double(free) / (gib * 1024))
        } else if Double(free) >= gib {
            return String(format: "%.0fG", Double(free) / gib)
        } else {
            return String(format: "%.0fM", Double(free) / (gib / 1024))
        }
    }

    private static func icon(for category: NodeCategory) -> String {
        switch category {
        case .applications: return "app.fill"
        case .caches: return "archivebox.fill"
        case .logs: return "doc.text.fill"
        case .stale: return "trash.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .system, .userData, .other: return "doc.fill"
        }
    }

    /// Recursive logical size of a directory (off-main use only).
    ///
    /// Hidden files ARE included now: the previous `.skipsHiddenFiles` meant
    /// dotfiles were silently excluded, so the displayed Trash/Downloads sizes
    /// were quietly wrong (short by whatever the hidden entries held).
    ///
    /// Bounded by `deadline`, `quickFolderMaxEntries` and `token`.
    nonisolated private static func directoryBytes(_ url: URL,
                                                   deadline: Date,
                                                   token: ScanCancellation) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        var visited = 0
        while let file = enumerator.nextObject() as? URL {
            visited += 1
            if visited & 0x3FF == 0 {
                if token.isCancelled { break }
                if Date() >= deadline { break }
                if visited > quickFolderMaxEntries { break }
            }
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               values.isDirectory != true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
