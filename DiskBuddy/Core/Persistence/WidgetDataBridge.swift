import Foundation

// MARK: - Widget/QuickLook data bridge (main app → App Group container)
//
// Writes a small snapshot JSON the desktop widget reads (free space, health
// grade, top hogs, forecast) and a duplicate index the Quick Look extension
// reads (path → copy count). Two transports for robustness with ad-hoc
// signing: the group-container file (canonical) and UserDefaults(suiteName:).

enum WidgetDataBridge {
    static let groupID = "group.com.diskdoom"

    struct Snapshot: Codable {
        var freeBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var healthGrade: String?
        var lastScanDate: Date?
        var daysUntilFull: Int?
        var topHogs: [Hog] = []
        var updatedAt: Date?

        struct Hog: Codable {
            var name: String
            var size: Int64
        }
    }

    /// Group container via entitlement; falls back to the well-known path
    /// (this app is non-sandboxed, so it can create it for dev builds).
    static var groupContainerURL: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        let direct = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(groupID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: direct, withIntermediateDirectories: true)
        return direct
    }

    /// Write the widget snapshot (capacity is read live here when not passed).
    static func write(
        freeBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        healthGrade: String?,
        lastScanDate: Date?,
        daysUntilFull: Int?,
        topHogs: [(name: String, size: Int64)]
    ) {
        var free = freeBytes ?? 0
        var total = totalBytes ?? 0
        if total == 0 {
            let url = URL(fileURLWithPath: "/")
            if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
               let capacity = values.volumeTotalCapacity {
                total = Int64(capacity)
                free = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            }
        }

        let snapshot = Snapshot(
            freeBytes: free,
            totalBytes: total,
            healthGrade: healthGrade,
            lastScanDate: lastScanDate,
            daysUntilFull: daysUntilFull,
            topHogs: topHogs.map { Snapshot.Hog(name: $0.name, size: $0.size) },
            updatedAt: Date())

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = groupContainerURL {
            try? data.write(to: url.appendingPathComponent("widget-data.json"), options: .atomic)
        }
        if let defaults = UserDefaults(suiteName: groupID) {
            defaults.set(data, forKey: "widget-data")
        }
    }

    /// Duplicate index for the Quick Look extension: path → copy count.
    /// Capped at 10k entries so the JSON stays light.
    static func writeDuplicateIndex(sets: [DuplicateSet]) {
        var index: [String: Int] = [:]
        var entries = 0
        for set in sets where entries < 10_000 {
            for file in set.files where entries < 10_000 {
                index[file.path] = set.files.count
                entries += 1
            }
        }
        guard let data = try? JSONEncoder().encode(index) else { return }
        if let url = groupContainerURL {
            try? data.write(to: url.appendingPathComponent("duplicates.json"), options: .atomic)
        }
        if let defaults = UserDefaults(suiteName: groupID) {
            defaults.set(data, forKey: "duplicates-index")
        }
    }
}
