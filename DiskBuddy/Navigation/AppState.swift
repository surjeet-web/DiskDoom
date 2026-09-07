import SwiftUI
import Combine
import AppKit

// MARK: - App state: real scan lifecycle, trash, snapshots, notifications, trial

@MainActor
final class AppState: ObservableObject {
    enum OnboardingStep { case welcome, fullDiskAccess, scanTarget }
    enum SidebarTab: String, CaseIterable {
        case explore, duplicates, applications, monitor, snapshots
        case litterScore, forecast, simulator, devCaches, health, budgets, liveFeed
        case lifecycle, provenance, compression, containers, privacy, photos
        case smartClean, storage
        var title: String {
            switch self {
            case .explore: return "Explore"
            case .duplicates: return "Duplicates"
            case .applications: return "Applications"
            case .monitor: return "Monitor"
            case .snapshots: return "Snapshots"
            case .litterScore: return "Litter Score"
            case .forecast: return "Forecast"
            case .simulator: return "What If?"
            case .devCaches: return "Dev Caches"
            case .health: return "Health"
            case .budgets: return "Budgets"
            case .liveFeed: return "Live Feed"
            case .lifecycle: return "Lifecycle"
            case .provenance: return "Provenance"
            case .compression: return "Compression"
            case .containers: return "Containers"
            case .privacy: return "Privacy"
            case .photos: return "Photos"
            case .smartClean: return "Smart Clean"
            case .storage: return "Storage"
            }
        }

        var symbol: String {
            switch self {
            case .explore: return "magnifyingglass"
            case .duplicates: return "doc.on.doc"
            case .applications: return "app.badge"
            case .monitor: return "chart.line.uptrend.xyaxis"
            case .snapshots: return "camera"
            case .litterScore: return "gauge.with.dots.needle.67percent"
            case .forecast: return "chart.line.uptrend.xyaxis"
            case .simulator: return "arrow.triangle.2.circlepath"
            case .devCaches: return "hammer.fill"
            case .health: return "heart.text.square"
            case .budgets: return "gauge.with.dots.needle.33percent"
            case .liveFeed: return "antenna.radiowaves.left.and.right"
            case .lifecycle: return "clock.arrow.circlepath"
            case .provenance: return "magnifyingglass.circle"
            case .compression: return "archivebox.fill"
            case .containers: return "square.grid.3x3.fill.square"
            case .privacy: return "lock.shield.fill"
            case .photos: return "photo.on.rectangle.angled"
            case .smartClean: return "sparkles"
            case .storage: return "internaldrive.fill"
            }
        }

        static var primary: [SidebarTab] {
            [.explore, .duplicates, .applications, .monitor, .snapshots]
        }

        static var insights: [SidebarTab] {
            [.smartClean, .litterScore, .forecast, .simulator, .devCaches, .health, .budgets, .liveFeed,
             .lifecycle, .provenance, .compression, .containers, .privacy, .photos, .storage]
        }
    }

    enum ExploreView: String, CaseIterable {
        case treemap, sunburst, flame, bubbles, mindMap, topSizes, ageMap, folderGrid
        var title: String {
            switch self {
            case .treemap: return "Treemap"
            case .sunburst: return "Sunburst"
            case .flame: return "Flame"
            case .bubbles: return "Bubbles"
            case .mindMap: return "MindMap"
            case .topSizes: return "Sizes"
            case .ageMap: return "Age"
            case .folderGrid: return "Grid"
            }
        }

        var symbol: String {
            switch self {
            case .treemap: return "square.grid.3x3.fill"
            case .sunburst: return "sun.max.fill"
            case .flame: return "flame.fill"
            case .bubbles: return "circle.dashed"
            case .mindMap: return "brain"
            case .topSizes: return "list.number"
            case .ageMap: return "calendar"
            case .folderGrid: return "square.grid.2x2.fill"
            }
        }
    }

    enum ScanPhase { case idle, scanning, done, failed }

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let actionTitle: String
        static func == (l: Banner, r: Banner) -> Bool { l.id == r.id }
    }

    // Services (injected by DiskBuddyApp).
    var permissions = PermissionsService()
    var notifications = NotificationService()
    var license = LicenseStore()
    let scanner = RealScanEngine()
    let dupFinder = DuplicateFinder()

    @Published var onboardingStep: OnboardingStep? = .welcome
    @Published var scanPhase: ScanPhase = .idle
    @Published var scanProgress: Double = 0
    @Published var scanPath: String = ""
    @Published var scanFiles: Int = 0
    @Published var scanElapsed: Double = 0
    @Published var scanTargetName = "Full Mac"
    @Published var limitedMode = false
    @Published var sidebarTab: SidebarTab = .explore
    @Published var exploreView: ExploreView = .treemap
    @Published var selectedNode: ScanNode? = nil
    @Published var inspectorVisible = true
    @Published var searchText = ""
    @Published var banner: Banner? = nil

    @Published var showCleanup = false
    @Published var showDeleteConfirm = false
    @Published var uninstallApp: AppEntry? = nil
    @Published var quickLookNode: ScanNode? = nil
    @Published var showLicense = false

    @Published var cleanupItems: [CleanupItem] = []
    @Published var duplicateKeeps: [UUID: UUID] = [:]
    @Published var snapshots: [Snapshot] = []
    @Published var compareIDs: [UUID] = []
    @Published var trashFailures: [TrashFailure] = []
    @Published var freedBytes: Int64 = 0
    @Published var freedCount: Int = 0

    // Real scan data (nil until first real scan; views fall back to mock).
    @Published var scanRoot: ScanNode? = nil
    @Published var records: [ScannedRecord] = []
    @Published var skippedPaths: [String] = []
    @Published var lastScanDate: Date? = nil

    // Settings (persisted).
    @Published var includeHidden = true
    @Published var followSymlinks = false
    @Published var maxDepth = 0
    @Published var excludedPaths: [String] = []
    @Published var dupMinBytes: Int64 = 10_000_000
    @Published var snapshotRetention = 30
    @Published var notifyOnScan = true
    @Published var monitorThresholdBytes: Int64 = 100_000_000
    @Published var scheduleFrequency = "never" // never/daily/weekly/monthly
    @Published var accentName = "system"

    private var scanTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var scanRootURL: URL = URL(fileURLWithPath: "/")

    init() {
        loadSettings()
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
        if let raw = UserDefaults.standard.string(forKey: "sidebarTab"),
           let tab = SidebarTab(rawValue: raw) { sidebarTab = tab }
        if let raw = UserDefaults.standard.string(forKey: "exploreView"),
           let view = ExploreView(rawValue: raw) { exploreView = view }
        inspectorVisible = UserDefaults.standard.object(forKey: "inspectorVisible") as? Bool ?? true
        scanner.$progress.receive(on: DispatchQueue.main).assign(to: &$scanProgress)
        scanner.$currentPath.receive(on: DispatchQueue.main).assign(to: &$scanPath)
        scanner.$filesFound.receive(on: DispatchQueue.main).assign(to: &$scanFiles)
    }

    // MARK: Derived data (real when available, mock fallback)

    var effectiveRoot: ScanNode { scanRoot ?? MockScanData.root }
    var effectiveTopLevel: [ScanNode] { effectiveRoot.children.isEmpty ? MockScanData.topLevel : effectiveRoot.children }

    var cleanupTotal: Int64 { cleanupItems.reduce(0) { $0 + $1.bytes } }

    var ageBuckets: [AgeBucket] {
        guard !records.isEmpty else { return MockAge.buckets }
        let now = Date()
        let day: TimeInterval = 86_400
        var totals = Array(repeating: Int64(0), count: 9)
        var counts = Array(repeating: 0, count: 9)
        for record in records where !record.isDirectory {
            let age = now.timeIntervalSince(record.modified)
            let bucket: Int
            switch age {
            case ..<day: bucket = 0
            case ..<(7 * day): bucket = 1
            case ..<(30 * day): bucket = 2
            case ..<(90 * day): bucket = 3
            case ..<(180 * day): bucket = 4
            case ..<(365 * day): bucket = 5
            case ..<(730 * day): bucket = 6
            default: bucket = age < 0 ? 0 : 7
            }
            totals[bucket] += record.bytes
            counts[bucket] += 1
        }
        let labels = ["Now (< 1 day)", "1 day – 1 week", "1 week – 1 month", "1 – 3 months",
                      "3 – 6 months", "6 – 12 months", "1 – 2 years", "2+ years", "Never modified"]
        let colors: [Color] = [.green, .green, .yellow, .yellow, .orange, .orange, .red, .red, .gray]
        return (0..<9).map { i in AgeBucket(label: labels[i], bytes: totals[i], files: counts[i], color: colors[i]) }
    }

    // MARK: Real scan lifecycle

    func finishOnboarding() { onboardingStep = nil }

    func startScan(target: String? = nil) {
        if let target { scanTargetName = target }
        scanRootURL = urlForTarget(scanTargetName)
        startRealScan()
    }

    func startRealScan(root: URL? = nil, label: String? = nil) {
        if let root { scanRootURL = root }
        if let label { scanTargetName = label }
        scanTask?.cancel()
        scanPhase = .scanning
        scanProgress = 0
        scanFiles = 0
        skippedPaths = []
        let startedAt = Date()
        // Full-disk scans skip kernel/virtual mounts and other volumes by
        // default — they cost minutes and contain no cleanable user data.
        // (Volumes are scanned individually from their own targets.)
        var excluded = excludedPaths.map { ($0 as NSString).expandingTildeInPath }
        if scanRootURL.path == "/" {
            excluded += ["/dev", "/Volumes", "/.Spotlight-V100", "/.fseventsd", "/System/Volumes/Update"]
        }
        let options = ScanOptions(
            includeHidden: includeHidden,
            followSymlinks: followSymlinks,
            maxDepth: maxDepth,
            excludedPaths: excluded)
        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await scanner.scan(root: scanRootURL, label: scanTargetName, options: options)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.scanElapsed = Date().timeIntervalSince(startedAt)
                self.applyResult(result)
            }
        }
    }

    private func urlForTarget(_ target: String) -> URL {
        if target.hasPrefix("/Volumes/") || target.hasPrefix("/") {
            return URL(fileURLWithPath: target)
        }
        switch target {
        case "Home Folder": return FileManager.default.homeDirectoryForCurrentUser
        default: return URL(fileURLWithPath: "/")
        }
    }

    private func applyResult(_ result: ScanResult) {
        scanRoot = result.root
        records = result.records
        skippedPaths = result.skipped
        lastScanDate = Date()
        UserDefaults.standard.set(lastScanDate, forKey: "lastScanDate")
        if result.root.fileCount == 0 {
            // Total failure (e.g. unreadable external volume) — nothing to show.
            scanPhase = .failed
        } else {
            scanPhase = .done
            selectedNode = result.root.children.first
            if result.isPartial {
                banner = Banner(
                    message: "Partial scan · \(result.skipped.count) folders unreadable · \(result.root.fileCount.formatted()) files mapped",
                    actionTitle: "Details")
            } else {
                banner = Banner(
                    message: "Scan complete · \(result.root.fileCount.formatted()) files · \(result.root.sizeString) · \(String(format: "%.1f", result.elapsed))s",
                    actionTitle: "View Results")
            }
            dismissBannerAfterDelay()
            if notifyOnScan {
                notifications.postScanComplete(files: result.root.fileCount, bytes: result.root.sizeBytes, seconds: result.elapsed)
            }
            saveSnapshotFromCurrentScan(label: "Scan")
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        // Keep previous results if any; otherwise idle.
        scanPhase = scanRoot == nil ? .idle : .done
    }

    func retryScan() {
        startRealScan()
    }

    // MARK: Cleanup queue (real Trash)

    func stage(source: String, path: String, bytes: Int64) {
        guard !cleanupItems.contains(where: { $0.path == path }) else { return }
        cleanupItems.append(CleanupItem(source: source, path: path, bytes: bytes))
    }

    func executeCleanup() {
        guard license.canClean else {
            banner = Banner(message: "Read-only mode — trial expired. Activate a license to clean.", actionTitle: "Activate")
            showDeleteConfirm = false
            return
        }
        let result = TrashService.trash(paths: cleanupItems.map { ($0.path, $0.bytes) })
        trashFailures = result.failures.map {
            TrashFailure(path: $0.path, bytes: $0.bytes, reason: $0.reason)
        }
        let failedPaths = Set(result.failures.map(\.path))
        cleanupItems.removeAll { failedPaths.contains($0.path) }
        freedBytes += result.trashedBytes
        freedCount += result.trashedCount
        showDeleteConfirm = false
        if result.failures.isEmpty {
            showCleanup = false
            banner = Banner(message: "Moved \(result.trashedCount) items to Trash · \(ByteFormatting.format(result.trashedBytes)) freed", actionTitle: "Show Trash")
            dismissBannerAfterDelay()
            notifications.postCleanupComplete(items: result.trashedCount, freed: result.trashedBytes)
        }
        // Else: queue sheet stays open showing the §31C failure report + retry.
    }

    func showTrashInFinder() {
        let trash = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(trash)
        banner = nil
    }

    func dismissBannerAfterDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.banner = nil
        }
    }

    // MARK: Snapshots (real persistence)

    func saveSnapshotFromCurrentScan(label: String) {
        guard let root = scanRoot else { return }
        var top: [String: Int64] = [:]
        for child in root.children { top[child.name] = child.sizeBytes }
        ScanStore.saveSnapshot(date: Date(), label: label, target: scanTargetName, totalBytes: root.sizeBytes, files: root.fileCount, topDirs: top)
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
    }

    func deleteSnapshot(_ snapshot: Snapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
    }

    // MARK: Settings persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(includeHidden, forKey: "setIncludeHidden")
        defaults.set(followSymlinks, forKey: "setFollowSymlinks")
        defaults.set(maxDepth, forKey: "setMaxDepth")
        defaults.set(excludedPaths, forKey: "setExcludedPaths")
        defaults.set(dupMinBytes, forKey: "setDupMinBytes")
        defaults.set(snapshotRetention, forKey: "setSnapshotRetention")
        defaults.set(notifyOnScan, forKey: "setNotifyOnScan")
        defaults.set(monitorThresholdBytes, forKey: "setMonitorThreshold")
        defaults.set(scheduleFrequency, forKey: "setScheduleFrequency")
        defaults.set(accentName, forKey: "setAccentName")
        defaults.set(sidebarTab.rawValue, forKey: "sidebarTab")
        defaults.set(exploreView.rawValue, forKey: "exploreView")
        defaults.set(inspectorVisible, forKey: "inspectorVisible")
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "setIncludeHidden") != nil {
            includeHidden = defaults.bool(forKey: "setIncludeHidden")
            followSymlinks = defaults.bool(forKey: "setFollowSymlinks")
            maxDepth = defaults.integer(forKey: "setMaxDepth")
            excludedPaths = defaults.stringArray(forKey: "setExcludedPaths") ?? []
            dupMinBytes = Int64(defaults.integer(forKey: "setDupMinBytes") == 0 ? 10_000_000 : defaults.integer(forKey: "setDupMinBytes"))
            snapshotRetention = defaults.integer(forKey: "setSnapshotRetention") == 0 ? 30 : defaults.integer(forKey: "setSnapshotRetention")
            notifyOnScan = defaults.bool(forKey: "setNotifyOnScan")
            if defaults.object(forKey: "setMonitorThreshold") != nil {
                monitorThresholdBytes = Int64(defaults.integer(forKey: "setMonitorThreshold"))
            }
            scheduleFrequency = defaults.string(forKey: "setScheduleFrequency") ?? "never"
            accentName = defaults.string(forKey: "setAccentName") ?? "system"
        }
    }

    // MARK: Scheduled scans (config persisted; fires on launch when due)

    func startupCheck() {
        license.refresh()
        Task { [weak self] in
            guard let self else { return }
            await license.validateOnLaunch()
            if let update = license.updateAvailable {
                banner = Banner(message: "Update \(update) is available (Check for Updates in Settings).", actionTitle: "Dismiss")
            } else if let message = license.lastServerMessage, !license.isLicensed {
                banner = Banner(message: message, actionTitle: "Activate")
            }
        }
        guard scheduleFrequency != "never" else { return }
        let last = UserDefaults.standard.object(forKey: "lastAutoScan") as? Date ?? .distantPast
        let interval: TimeInterval
        switch scheduleFrequency {
        case "daily": interval = 86_400
        case "weekly": interval = 7 * 86_400
        default: interval = 30 * 86_400
        }
        if Date().timeIntervalSince(last) >= interval {
            UserDefaults.standard.set(Date(), forKey: "lastAutoScan")
            startRealScan()
        }
    }
}
