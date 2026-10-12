import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Real persistence: JSON scan cache + snapshots + CSV export
//
// ~/Library/Application Support/DiskBuddy/ — snapshots pruned to retention,
// corrupted cache is deleted silently and treated as "no cache" (feature 124).

struct StoredSnapshot: Codable {
    let date: Date
    let label: String
    let target: String
    let totalBytes: Int64
    let files: Int
    let topDirs: [String: Int64] // top-level name → bytes (for comparison)
}

enum ScanStore {
    /// Test hook: redirect snapshot storage (unit tests use a temp directory).
    static var directoryOverride: URL?

    private static var baseURL: URL {
        directoryOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DiskBuddy", isDirectory: true)
    }

    private static var snapshotsURL: URL {
        baseURL.appendingPathComponent("snapshots", isDirectory: true)
    }

    static func loadSnapshots(retention: Int) -> [Snapshot] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: snapshotsURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }
        var loaded: [StoredSnapshot] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data)
            else {
                try? fm.removeItem(at: file) // corrupted → delete silently, keep going
                continue
            }
            loaded.append(stored)
        }
        loaded.sort { $0.date > $1.date }
        // Prune beyond retention.
        if loaded.count > retention {
            for extra in loaded[retention...] { removeSnapshot(date: extra.date) }
            loaded = Array(loaded.prefix(retention))
        }
        return loaded.map {
            Snapshot(date: $0.date, label: $0.label, totalBytes: $0.totalBytes, files: $0.files, target: $0.target)
        }
    }

    static func saveSnapshot(date: Date, label: String, target: String, totalBytes: Int64, files: Int, topDirs: [String: Int64]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        let stored = StoredSnapshot(date: date, label: label, target: target, totalBytes: totalBytes, files: files, topDirs: topDirs)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let stamp = Int(date.timeIntervalSince1970 * 1_000_000_000)
        var url = snapshotsURL.appendingPathComponent("snapshot-\(stamp).json")
        var attempt = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = snapshotsURL.appendingPathComponent("snapshot-\(stamp)-\(attempt).json")
            attempt += 1
        }
        try? data.write(to: url, options: .atomic)
    }

    static func removeSnapshot(date: Date) {
        let prefix = "snapshot-\(Int(date.timeIntervalSince1970))"
        guard let files = try? FileManager.default.contentsOfDirectory(at: snapshotsURL, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Look up stored top-dir sizes for comparison (nil if snapshot predates storage).
    static func topDirs(for snapshot: Snapshot) -> [String: Int64]? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: snapshotsURL, includingPropertiesForKeys: nil) else { return nil }
        let prefix = "snapshot-\(Int(snapshot.date.timeIntervalSince1970))"
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let stored = try? JSONDecoder().decode(StoredSnapshot.self, from: data) {
                return stored.topDirs
            }
        }
        return nil
    }
}

// MARK: - CSV export (real file data; save panel runs on main)

@MainActor
enum ExportService {
    static func csvURL(rows: [[String]], suggestedName: String) -> URL? {
        var text = ""
        for row in rows {
            text += row.map { field in
                "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: ",") + "\n"
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
