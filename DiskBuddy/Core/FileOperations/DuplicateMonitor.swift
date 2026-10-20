import Foundation
import Combine
import UserNotifications

// MARK: - Duplicate monitor
//
// The reference app's "Duplicate Monitor" watches chosen folders on a schedule
// and reports new duplicates. This implementation rescans the watched folders
// on a timer, compares stable set identities with the previous pass, and
// notifies only about newly discovered sets. Manual checks are always allowed.

enum DuplicateMonitorInterval: String, CaseIterable, Identifiable {
    case manual
    case fifteenMinutes
    case hourly
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manually"
        case .fifteenMinutes: return "Every 15 minutes"
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .manual: return nil
        case .fifteenMinutes: return 15 * 60
        case .hourly: return 60 * 60
        case .daily: return 24 * 60 * 60
        }
    }
}

enum CleanupReminderFrequency: String, CaseIterable, Identifiable {
    case never
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: return "Never"
        case .weekly: return "Once a week"
        case .biweekly: return "Once in two weeks"
        case .monthly: return "Once a month"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .weekly: return 7 * 24 * 60 * 60
        case .biweekly: return 14 * 24 * 60 * 60
        case .monthly: return 30 * 24 * 60 * 60
        }
    }
}

@MainActor
final class DuplicateMonitor: ObservableObject {
    @Published private(set) var folders: [String] = []
    @Published var interval: DuplicateMonitorInterval = .manual {
        didSet { UserDefaults.standard.set(interval.rawValue, forKey: Self.intervalKey); restartTimer() }
    }
    @Published private(set) var lastCheck: Date?
    @Published private(set) var lastNewSets = 0
    @Published private(set) var lastTotalSets = 0
    @Published private(set) var lastPotentialBytes: Int64 = 0
    @Published private(set) var isChecking = false
    @Published private(set) var statusMessage = "Idle"
    @Published var cleanupReminder: CleanupReminderFrequency = .never {
        didSet {
            UserDefaults.standard.set(cleanupReminder.rawValue, forKey: Self.reminderKey)
            applyCleanupReminder()
        }
    }

    private static let foldersKey = "monitorFolders"
    private static let intervalKey = "monitorInterval"
    private static let reminderKey = "cleanupReminder"
    private static let reminderID = "diskdoom-cleanup-reminder"

    private var timer: Timer?
    private var checkTask: Task<Void, Never>?
    /// Folder → set identities from the previous pass.
    private var knownSets: [String: Set<UUID>] = [:]

    init() {
        folders = (UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? [])
            .map { ($0 as NSString).expandingTildeInPath }
        interval = DuplicateMonitorInterval(
            rawValue: UserDefaults.standard.string(forKey: Self.intervalKey) ?? "") ?? .manual
        cleanupReminder = CleanupReminderFrequency(
            rawValue: UserDefaults.standard.string(forKey: Self.reminderKey) ?? "") ?? .never
    }

    // MARK: Folders

    @discardableResult
    func addFolder(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), !folders.contains(expanded) else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        folders.append(expanded)
        folders.sort()
        persistFolders()
        return true
    }

    func removeFolder(_ path: String) {
        folders.removeAll { $0 == path }
        knownSets.removeValue(forKey: path)
        persistFolders()
    }

    func clearFolders() {
        folders.removeAll()
        knownSets.removeAll()
        persistFolders()
    }

    // MARK: Timer

    func start() {
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        checkTask?.cancel()
        checkTask = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard let seconds = interval.seconds, !folders.isEmpty else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkNow()
            }
        }
        timer.tolerance = min(60, seconds * 0.1)
        self.timer = timer
    }

    private func persistFolders() {
        UserDefaults.standard.set(folders, forKey: Self.foldersKey)
        restartTimer()
    }

    // MARK: Check

    /// Seconds since the last check, for the UI.
    var lastCheckLabel: String {
        guard let lastCheck else { return "Never" }
        return lastCheck.formatted(date: .abbreviated, time: .shortened)
    }

    func checkNow() async {
        guard !isChecking else { return }
        guard !folders.isEmpty else {
            statusMessage = "Add a folder to watch."
            return
        }
        isChecking = true
        statusMessage = "Checking \(folders.count) folder\(folders.count == 1 ? "" : "s")…"
        let snapshot = folders
        let results = await Task.detached(priority: .utility) {
            await Self.scanFolders(snapshot)
        }.value
        guard !Task.isCancelled else {
            isChecking = false
            return
        }
        var totalSets = 0
        var newSets = 0
        var potential: Int64 = 0
        for result in results {
            totalSets += result.sets.count
            let identities = Set(result.sets.map(\.id))
            let previous = knownSets[result.folder]
            let freshlyFound = previous.map { identities.subtracting($0) } ?? []
            newSets += freshlyFound.count
            knownSets[result.folder] = identities
            potential += result.sets.reduce(0) { $0 + $1.reclaimable }
            if result.skipped {
                statusMessage = "\(result.folder) was only partially readable"
            }
        }
        lastCheck = Date()
        lastTotalSets = totalSets
        lastNewSets = newSets
        lastPotentialBytes = potential
        isChecking = false
        if totalSets == 0 {
            statusMessage = "No duplicates in watched folders."
        } else if newSets > 0 {
            statusMessage = "\(newSets) new set\(newSets == 1 ? "" : "s") · \(potential.fileSizeString) potential"
            NotificationService.shared.postDuplicateAlert(
                newSets: newSets, folderCount: snapshot.count, bytes: potential)
        } else {
            statusMessage = "No new duplicates · \(totalSets) known set\(totalSets == 1 ? "" : "s")"
        }
    }

    private struct FolderResult: Sendable {
        let folder: String
        let sets: [DuplicateSet]
        let skipped: Bool
    }

    nonisolated private static func scanFolders(_ folders: [String]) async -> [FolderResult] {
        var results: [FolderResult] = []
        for folder in folders {
            if Task.isCancelled { break }
            let url = URL(fileURLWithPath: folder)
            let options = ScanOptions(
                includeHidden: false, followSymlinks: false, maxDepth: 0,
                excludedPaths: [], maxFiles: 300_000,
                maxChildrenPerDir: 300, collapseSmartLeaves: true,
                maxNodes: 300_000, maxScanSeconds: 90)
            let scan = await RealScanEngine().scan(root: url, label: url.lastPathComponent, options: options)
            let sets = await DuplicateFinder.findSets(records: scan.records, minBytes: 1_000_000)
            results.append(FolderResult(folder: folder, sets: sets, skipped: !scan.skipped.isEmpty))
        }
        return results
    }

    // MARK: Cleanup reminder

    private func applyCleanupReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        guard let seconds = cleanupReminder.seconds else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to clean up"
        content.body = "Run a duplicate scan to keep your Mac tidy."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: true)
        center.add(UNNotificationRequest(identifier: Self.reminderID,
                                         content: content, trigger: trigger))
    }
}
