import SwiftUI

// MARK: - Prototype mock models for §10/11/15/16/18/19/20/21/22

private let GB: Int64 = 1_000_000_000
private let MB: Int64 = 1_000_000

extension Int64 {
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: Duplicates (§15)

struct DuplicateFile: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let bytes: Int64
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: DuplicateFile, r: DuplicateFile) -> Bool { l.id == r.id }
}

struct DuplicateSet: Identifiable, Hashable {
    let id = UUID()
    let hashPrefix: String
    let files: [DuplicateFile]

    var perCopy: Int64 { files.first?.bytes ?? 0 }
    var total: Int64 { perCopy * Int64(files.count) }
    var reclaimable: Int64 { perCopy * Int64(max(files.count - 1, 0)) }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: DuplicateSet, r: DuplicateSet) -> Bool { l.id == r.id }
}

enum MockDuplicates {
    static let sets: [DuplicateSet] = [
        DuplicateSet(hashPrefix: "sha256: a3f2b1…c9", files: [
            DuplicateFile(path: "~/Downloads/photo_2024.jpg", bytes: 420 * MB),
            DuplicateFile(path: "~/Desktop/photo.jpg", bytes: 420 * MB),
            DuplicateFile(path: "~/Documents/backup/photo.jpg", bytes: 420 * MB),
            DuplicateFile(path: "/Volumes/Backup/photo.jpg", bytes: 420 * MB),
        ]),
        DuplicateSet(hashPrefix: "sha256: 77de04…1a", files: [
            DuplicateFile(path: "~/Downloads/installer-2.dmg", bytes: 180 * MB),
            DuplicateFile(path: "~/Desktop/installer.dmg", bytes: 180 * MB),
            DuplicateFile(path: "/Volumes/Backup/installer.dmg", bytes: 180 * MB),
        ]),
        DuplicateSet(hashPrefix: "sha256: b91c33…e7", files: [
            DuplicateFile(path: "~/Movies/export-final.mp4", bytes: 900 * MB),
            DuplicateFile(path: "~/Movies/export-final-2.mp4", bytes: 900 * MB),
        ]),
    ]

    static let totalReclaimable: Int64 = sets.reduce(0) { $0 + $1.reclaimable }
}

// MARK: Applications (§16)

struct AppEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleID: String
    let bundleBytes: Int64
    let artifactBytes: Int64
    let symbol: String
    let tint: Color
    let isStale: Bool
    let installedDaysAgo: Int

    var totalBytes: Int64 { bundleBytes + artifactBytes }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: AppEntry, r: AppEntry) -> Bool { l.id == r.id }
}

enum MockApps {
    static let all: [AppEntry] = [
        AppEntry(name: "Google Chrome", bundleID: "com.google.Chrome", bundleBytes: Int64(4.1 * Double(GB)), artifactBytes: Int64(8.3 * Double(GB)), symbol: "globe", tint: .blue, isStale: false, installedDaysAgo: 400),
        AppEntry(name: "Xcode", bundleID: "com.apple.dt.Xcode", bundleBytes: Int64(5.1 * Double(GB)), artifactBytes: Int64(3.1 * Double(GB)), symbol: "hammer.fill", tint: .blue, isStale: false, installedDaysAgo: 200),
        AppEntry(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", bundleBytes: Int64(1.2 * Double(GB)), artifactBytes: Int64(3.9 * Double(GB)), symbol: "message.fill", tint: .green, isStale: false, installedDaysAgo: 300),
        AppEntry(name: "Figma", bundleID: "com.figma.Desktop", bundleBytes: Int64(0.9 * Double(GB)), artifactBytes: Int64(3.4 * Double(GB)), symbol: "paintbrush.fill", tint: .purple, isStale: false, installedDaysAgo: 120),
        AppEntry(name: "Spotify", bundleID: "com.spotify.client", bundleBytes: Int64(0.7 * Double(GB)), artifactBytes: Int64(3.4 * Double(GB)), symbol: "music.note", tint: .green, isStale: false, installedDaysAgo: 500),
        AppEntry(name: "Old VPN Client", bundleID: "com.oldvpn.client", bundleBytes: 0, artifactBytes: 420 * MB, symbol: "lock.fill", tint: .gray, isStale: true, installedDaysAgo: 900),
        AppEntry(name: "Beta Editor", bundleID: "com.beta.editor", bundleBytes: 0, artifactBytes: 180 * MB, symbol: "pencil", tint: .gray, isStale: true, installedDaysAgo: 700),
    ]
}

// MARK: Processes (§19)

struct ProcEntry: Identifiable, Hashable {
    let id = UUID()
    let pid: Int
    let name: String
    var cpu: Double
    var memoryBytes: Int64
    let threads: Int
    let isSystem: Bool
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: ProcEntry, r: ProcEntry) -> Bool { l.id == r.id }
}

enum MockProcesses {
    static let all: [ProcEntry] = [
        ProcEntry(pid: 4231, name: "Google Chrome", cpu: 18.2, memoryBytes: Int64(1.8 * Double(GB)), threads: 42, isSystem: false),
        ProcEntry(pid: 1892, name: "Xcode", cpu: 12.1, memoryBytes: Int64(2.4 * Double(GB)), threads: 89, isSystem: false),
        ProcEntry(pid: 891, name: "Slack", cpu: 8.4, memoryBytes: 820 * MB, threads: 23, isSystem: false),
        ProcEntry(pid: 5102, name: "Spotify", cpu: 4.2, memoryBytes: 340 * MB, threads: 12, isSystem: false),
        ProcEntry(pid: 234, name: "Finder", cpu: 2.1, memoryBytes: 180 * MB, threads: 8, isSystem: true),
        ProcEntry(pid: 102, name: "WindowServer", cpu: 1.8, memoryBytes: 420 * MB, threads: 14, isSystem: true),
        ProcEntry(pid: 89, name: "kernel_task", cpu: 1.4, memoryBytes: 380 * MB, threads: 128, isSystem: true),
        ProcEntry(pid: 6201, name: "Docker", cpu: 0.8, memoryBytes: Int64(1.2 * Double(GB)), threads: 34, isSystem: false),
        ProcEntry(pid: 2103, name: "mds", cpu: 0.6, memoryBytes: 84 * MB, threads: 12, isSystem: true),
    ]
}

// MARK: Age buckets (§11)

struct AgeBucket: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let bytes: Int64
    let files: Int
    let color: Color
}

enum MockAge {
    static let buckets: [AgeBucket] = [
        AgeBucket(label: "Now (< 1 day)", bytes: 24 * GB, files: 182_004, color: .green),
        AgeBucket(label: "1 day – 1 week", bytes: 18 * GB, files: 140_882, color: .green),
        AgeBucket(label: "1 week – 1 month", bytes: 42 * GB, files: 301_552, color: .yellow),
        AgeBucket(label: "1 – 3 months", bytes: 38 * GB, files: 280_114, color: .yellow),
        AgeBucket(label: "3 – 6 months", bytes: 22 * GB, files: 160_209, color: .orange),
        AgeBucket(label: "6 – 12 months", bytes: 14 * GB, files: 98_445, color: .orange),
        AgeBucket(label: "1 – 2 years", bytes: 42 * GB, files: 250_881, color: .red),
        AgeBucket(label: "2+ years", bytes: 48 * GB, files: 310_204, color: .red),
        AgeBucket(label: "Never modified", bytes: 8 * GB, files: 168_050, color: .gray),
    ]
}

// MARK: Snapshots (§20/§21)

struct Snapshot: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let label: String
    let totalBytes: Int64
    let files: Int
    let target: String
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Snapshot, r: Snapshot) -> Bool { l.id == r.id }
}

enum MockSnapshots {
    static let initial: [Snapshot] = {
        let now = Date()
        let day: TimeInterval = 86_400
        return [
            Snapshot(date: now, label: "Today", totalBytes: 256 * GB, files: 1_892_341, target: "Full Mac"),
            Snapshot(date: now - day, label: "Yesterday", totalBytes: Int64(253.9 * Double(GB)), files: 1_889_102, target: "Full Mac"),
            Snapshot(date: now - 7 * day, label: "Last Monday", totalBytes: 262 * GB, files: 1_885_234, target: "Full Mac"),
        ]
    }()

    struct DeltaRow: Identifiable {
        let id = UUID()
        let name: String
        let oldBytes: Int64
        let newBytes: Int64
        var delta: Int64 { newBytes - oldBytes }
    }

    static let comparison: [DeltaRow] = [
        DeltaRow(name: "Google Chrome Caches", oldBytes: Int64(8.2 * Double(GB)), newBytes: Int64(9.4 * Double(GB))),
        DeltaRow(name: "Xcode DerivedData", oldBytes: Int64(3.1 * Double(GB)), newBytes: Int64(3.9 * Double(GB))),
        DeltaRow(name: "Slack HTTPStorage", oldBytes: Int64(1.8 * Double(GB)), newBytes: Int64(2.2 * Double(GB))),
        DeltaRow(name: "~/Downloads", oldBytes: Int64(6.8 * Double(GB)), newBytes: Int64(7.0 * Double(GB))),
        DeltaRow(name: "Spotify Caches", oldBytes: Int64(5.4 * Double(GB)), newBytes: Int64(5.1 * Double(GB))),
        DeltaRow(name: "Docker", oldBytes: Int64(1.9 * Double(GB)), newBytes: Int64(1.9 * Double(GB))),
    ]
}

// MARK: Cleanup queue (§22)

struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let source: String
    let path: String
    let bytes: Int64
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: CleanupItem, r: CleanupItem) -> Bool { l.id == r.id }
}
