import Foundation

// MARK: - Widget/QuickLook data bridge (main app → App Group container)
//
// Writes a small snapshot JSON the desktop widget reads (free space, health
// grade, top hogs, forecast) and a duplicate index the Quick Look extension
// reads (dated, last-scan path → copy count). Two transports for robustness with ad-hoc
// signing: the group-container file (canonical) and UserDefaults(suiteName:).

enum WidgetDataBridge {
    static let groupID = "group.com.diskdoom"

    struct Snapshot: Codable {
        var schemaVersion: Int = 2
        var capacity: Measurement<StorageCapacity>?
        var scanSource: String?
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
        let now = Date()
        let capacity: Measurement<StorageCapacity>
        if let freeBytes, let totalBytes {
            if let value = StorageCapacity(totalBytes: totalBytes, freeBytes: freeBytes) {
                capacity = .available(value: value, measuredAt: now, source: "App volume measurement")
            } else {
                capacity = .unavailable(reason: "Invalid volume capacity")
            }
        } else {
            capacity = StorageCapacityReader.read(measuredAt: now)
        }

        let snapshot = Snapshot(
            capacity: capacity,
            scanSource: lastScanDate == nil ? nil : "DiskDoom scan",
            freeBytes: capacity.availableValue?.freeBytes ?? 0,
            totalBytes: capacity.availableValue?.totalBytes ?? 0,
            healthGrade: healthGrade,
            lastScanDate: lastScanDate,
            daysUntilFull: daysUntilFull,
            topHogs: topHogs.map { Snapshot.Hog(name: $0.name, size: $0.size) },
            updatedAt: now)

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = groupContainerURL {
            try? data.write(to: url.appendingPathComponent("widget-data.json"), options: .atomic)
        }
        if let defaults = UserDefaults(suiteName: groupID) {
            defaults.set(data, forKey: "widget-data")
        }
    }

    /// Duplicate index for the Quick Look extension: last-scan path → copy count.
    /// `scannedAt` records result publication, not verification at preview time.
    /// Capped at 10k entries so the JSON stays light.
    static func writeDuplicateIndex(sets: [DuplicateSet], scannedAt: Date = Date()) {
        var index: [String: Int] = [:]
        var entries = 0
        for set in sets where entries < 10_000 {
            for file in set.files where entries < 10_000 {
                index[file.path] = set.files.count
                entries += 1
            }
        }
        struct DuplicateSnapshot: Codable {
            let schemaVersion: Int
            let scannedAt: Date
            let source: String
            let counts: [String: Int]
        }
        let snapshot = DuplicateSnapshot(schemaVersion: 2, scannedAt: scannedAt,
                                         source: "DiskDoom duplicate scan", counts: index)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = groupContainerURL {
            try? data.write(to: url.appendingPathComponent("duplicates.json"), options: .atomic)
        }
        if let defaults = UserDefaults(suiteName: groupID) {
            defaults.set(data, forKey: "duplicates-index")
        }
    }
}
