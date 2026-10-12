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

struct AppEntry: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let bundleID: String
    let bundlePath: String // "" for stale entries (no bundle on disk)
    let version: String
    let bundleBytes: Int64
    let artifacts: [AppArtifactInfo]
    let installDate: Date?
    let isStale: Bool

    var artifactBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { bundleBytes + artifactBytes }
    var installedDaysAgo: Int? {
        installDate.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: AppEntry, r: AppEntry) { l.id == r.id }

    private enum CodingKeys: String, CodingKey {
        case id, name, bundleID, bundlePath, version, bundleBytes, artifacts, installDate, isStale
    }
    init(name: String, bundleID: String, bundlePath: String, version: String,
         bundleBytes: Int64, artifacts: [AppArtifactInfo], installDate: Date?, isStale: Bool) {
        self.id = UUID()
        self.name = name
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.version = version
        self.bundleBytes = bundleBytes
        self.artifacts = artifacts
        self.installDate = installDate
        self.isStale = isStale
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        bundlePath = try c.decode(String.self, forKey: .bundlePath)
        version = try c.decode(String.self, forKey: .version)
        bundleBytes = try c.decode(Int64.self, forKey: .bundleBytes)
        artifacts = try c.decode([AppArtifactInfo].self, forKey: .artifacts)
        installDate = try c.decodeIfPresent(Date.self, forKey: .installDate)
        isStale = try c.decode(Bool.self, forKey: .isStale)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(bundlePath, forKey: .bundlePath)
        try c.encode(version, forKey: .version)
        try c.encode(bundleBytes, forKey: .bundleBytes)
        try c.encode(artifacts, forKey: .artifacts)
        try c.encodeIfPresent(installDate, forKey: .installDate)
        try c.encode(isStale, forKey: .isStale)
    }
}

enum MockApps {
    // Pre-inventory fallback so the tab is never blank (replaced by real data).
    static let all: [AppEntry] = [
        AppEntry(
            name: "Google Chrome", bundleID: "com.google.Chrome", bundlePath: "/Applications/Google Chrome.app",
            version: "124.0", bundleBytes: Int64(4.1 * Double(GB)),
            artifacts: [
                AppArtifactInfo(path: "~/Library/Caches/com.google.Chrome", bytes: Int64(5.2 * Double(GB)), kind: "Caches"),
                AppArtifactInfo(path: "~/Library/HTTPStorages/com.google.Chrome", bytes: Int64(2.1 * Double(GB)), kind: "HTTPStorages"),
                AppArtifactInfo(path: "~/Library/Application Support/Google/Chrome", bytes: 600_000_000, kind: "Application Support"),
                AppArtifactInfo(path: "~/Library/Saved Application State/com.google.Chrome.savedState", bytes: 200_000_000, kind: "Saved State"),
                AppArtifactInfo(path: "~/Library/Preferences/com.google.Chrome.plist", bytes: 12_000, kind: "Preferences"),
                AppArtifactInfo(path: "~/Library/WebKit/com.google.Chrome", bytes: 100_000_000, kind: "WebKit"),
                AppArtifactInfo(path: "~/Library/LaunchAgents/com.google.keystone.agent.plist", bytes: 4_000, kind: "Launch Agent"),
                AppArtifactInfo(path: "~/Library/Logs/GoogleSoftwareUpdate", bytes: 8_000, kind: "Logs"),
            ],
            installDate: Calendar.current.date(byAdding: .day, value: -400, to: Date()), isStale: false),
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
