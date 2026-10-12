import Foundation
import AppKit

// MARK: - D5 App Lifecycle Timeline (ObservableObject, matches codebase DI)
//
// Review fixes applied:
// - NO file atime fallback: "last launch" comes only from tracked launch
//   history (NSWorkspace watcher, persisted). Unknown stays .unknown.
// - The NSWorkspace observer token is retained and removed (deinit/stop).

struct AppLifecycleEntry: Identifiable {
    let id = UUID()
    let appName: String
    let bundleID: String
    let path: String
    let installDate: Date?
    let lastLaunch: Date?
    let launchCount: Int
    let daysSinceLastLaunch: Int? // raw day count, nil when unknown
    let bytes: Int64
    let status: LifecycleStatus

    enum LifecycleStatus: String, CaseIterable {
        case active, occasional, dormant, abandoned, unknown

        var label: String {
            switch self {
            case .active: return "Active"
            case .occasional: return "Occasional"
            case .dormant: return "Dormant"
            case .abandoned: return "Abandoned"
            case .unknown: return "Unknown"
            }
        }
    }

    static func status(forDays days: Int?) -> LifecycleStatus {
        guard let days else { return .unknown }
        switch days {
        case 0...7: return .active
        case 8...30: return .occasional
        case 31...90: return .dormant
        default: return .abandoned
        }
    }
}

struct AppUsageHistory: Codable {
    var launchDates: [Date] = []

    mutating func recordLaunch(_ date: Date = Date()) {
        launchDates.append(date)
        if launchDates.count > 200 { launchDates = Array(launchDates.suffix(200)) }
    }
}

// Sendable weak box: the NSWorkspace observer block is @Sendable and must
// not capture the non-Sendable engine directly.
private final class WeakLifecycleEngine: @unchecked Sendable {
    weak var value: AppLifecycleEngine?
}

// Main-confined in practice (driven only from UI/main thread), hence Sendable.
final class AppLifecycleEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var entries: [AppLifecycleEntry] = []

    private var history: [String: AppUsageHistory] = [:]
    private var launchObserver: NSObjectProtocol?
    private let historyKey = "appUsageHistory"

    init() {
        loadHistory()
    }

    deinit {
        stopLaunchWatcher()
    }

    /// Real computation from the app inventory + tracked launch history.
    /// Unknown history stays .unknown — nothing is fabricated.
    func compute(apps: [AppEntry]) {
        let day: TimeInterval = 86_400
        entries = apps
            .filter { !$0.isStale && !$0.bundlePath.isEmpty }
            .map { app in
                let tracked = history[app.bundleID]?.launchDates ?? []
                let lastLaunch = tracked.last
                let count = tracked.count
                let days = lastLaunch.map { max(0, Int(Date().timeIntervalSince($0) / day)) }
                return AppLifecycleEntry(
                    appName: app.name,
                    bundleID: app.bundleID,
                    path: app.bundlePath,
                    installDate: app.installDate,
                    lastLaunch: lastLaunch,
                    launchCount: count,
                    daysSinceLastLaunch: days,
                    bytes: app.totalBytes,
                    status: AppLifecycleEntry.status(forDays: days))
            }
            .sorted {
                // Abandoned first, then stalest.
                if ($0.status == .abandoned) != ($1.status == .abandoned) {
                    return $0.status == .abandoned
                }
                return ($0.daysSinceLastLaunch ?? 9999) > ($1.daysSinceLastLaunch ?? 9999)
            }
    }

    /// Tracked days since last launch per bundle ID (empty until launches are observed).
    var trackedDaysSinceLaunch: [String: Int] {
        let day: TimeInterval = 86_400
        var result: [String: Int] = [:]
        for (id, h) in history {
            if let last = h.launchDates.last {
                result[id] = max(0, Int(Date().timeIntervalSince(last) / day))
            }
        }
        return result
    }

    // MARK: Live launch tracking (retained observer, removed on stop/deinit)

    func startLaunchWatcher() {
        guard launchObserver == nil else { return }
        let box = WeakLifecycleEngine()
        box.value = self
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main)
        { [box] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier
            else { return }
            box.value?.recordLaunch(bundleID: bundleID)
        }
    }

    func stopLaunchWatcher() {
        if let observer = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            launchObserver = nil
        }
    }

    func recordLaunch(bundleID: String, date: Date = Date()) {
        var h = history[bundleID] ?? AppUsageHistory()
        h.recordLaunch(date)
        history[bundleID] = h
        saveHistory()
    }

    var abandoned: [AppLifecycleEntry] { entries.filter { $0.status == .abandoned } }
    var abandonedBytes: Int64 { abandoned.reduce(0) { $0 + $1.bytes } }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([String: AppUsageHistory].self, from: data)
        else { return }
        history = decoded
    }
}
