import SwiftUI

// MARK: - Scan model (prototype mock data matching spec §05 annotations)

enum NodeCategory: String, CaseIterable, Hashable, Codable, Sendable {
    case applications, system, userData, caches, logs, stale, duplicates, other

    var label: String {
        switch self {
        case .applications: return "Apps"
        case .system: return "System"
        case .userData: return "Users"
        case .caches: return "Caches"
        case .logs: return "Logs"
        case .stale: return "Stale"
        case .duplicates: return "Duplicates"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .applications: return .categoryApplications
        case .system: return .categorySystem
        case .userData: return .categoryUserData
        case .caches: return .categoryCaches
        case .logs: return .categoryLogs
        case .stale: return .categoryStale
        case .duplicates: return .categoryDuplicates
        case .other: return .categoryOther
        }
    }

    var symbol: String {
        switch self {
        case .applications: return "app.fill"
        case .system: return "gear.circle.fill"
        case .userData: return "person.fill"
        case .caches: return "archivebox.fill"
        case .logs: return "doc.text.fill"
        case .stale: return "trash.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .other: return "questionmark.folder.fill"
        }
    }
}

struct ScanNode: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let sizeBytes: Int64
    let category: NodeCategory
    let fileCount: Int
    var children: [ScanNode] = []
    /// Real scan metadata (nil for mock data).
    let modified: Date?
    let physicalBytes: Int64?
    /// Smart-leaf collapsing: aggregate measured without per-file indexing.
    /// Double-click expands on demand.
    let isCollapsed: Bool
    let collapseReason: String?

    init(id: UUID = UUID(), name: String, path: String, sizeBytes: Int64, category: NodeCategory, fileCount: Int, children: [ScanNode] = [], modified: Date? = nil, physicalBytes: Int64? = nil, isCollapsed: Bool = false, collapseReason: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.category = category
        self.fileCount = fileCount
        self.children = children
        self.modified = modified
        self.physicalBytes = physicalBytes
        self.isCollapsed = isCollapsed
        self.collapseReason = collapseReason
    }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    /// Tooltip text per spec §05 Treemap Tooltip.
    var tooltip: String {
        "\(name)\n\(sizeString) · \(fileCount.formatted()) files"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ScanNode, rhs: ScanNode) -> Bool { lhs.id == rhs.id }
}

// MARK: - Mock scan tree (spec §05: 256 GB used, 1,892,341 files)

private let GB: Int64 = 1_000_000_000

enum MockScanData {
    static let totalBytes: Int64 = 256 * GB
    static let totalFiles = 1_892_341
    static let reclaimableBytes: Int64 = 142 * GB
    static let scanSeconds = 9.2

    static let root: ScanNode = ScanNode(
        name: "Macintosh HD",
        path: "/",
        sizeBytes: 256 * GB,
        category: .system,
        fileCount: totalFiles,
        children: [
            ScanNode(
                name: "Users", path: "/Users", sizeBytes: 72 * GB,
                category: .userData, fileCount: 412_008, children: [
                    ScanNode(name: "you", path: "/Users/you", sizeBytes: 42 * GB, category: .userData, fileCount: 301_122),
                    ScanNode(name: "Shared", path: "/Users/Shared", sizeBytes: 30 * GB, category: .userData, fileCount: 110_886),
                ]),
            ScanNode(
                name: "System", path: "/System", sizeBytes: 62 * GB,
                category: .system, fileCount: 388_401),
            ScanNode(
                name: "Applications", path: "/Applications", sizeBytes: 48 * GB,
                category: .applications, fileCount: 891_234, children: [
                    ScanNode(name: "Google Chrome", path: "/Applications/Google Chrome.app", sizeBytes: Int64(12.4 * Double(GB)), category: .applications, fileCount: 142_391),
                    ScanNode(name: "Xcode", path: "/Applications/Xcode.app", sizeBytes: Int64(8.2 * Double(GB)), category: .applications, fileCount: 98_104),
                    ScanNode(name: "Slack", path: "/Applications/Slack.app", sizeBytes: Int64(5.1 * Double(GB)), category: .applications, fileCount: 41_208),
                    ScanNode(name: "Figma", path: "/Applications/Figma.app", sizeBytes: Int64(4.3 * Double(GB)), category: .applications, fileCount: 33_917),
                    ScanNode(name: "Spotify", path: "/Applications/Spotify.app", sizeBytes: Int64(4.1 * Double(GB)), category: .applications, fileCount: 29_552),
                    ScanNode(name: "Other (418 apps)", path: "/Applications", sizeBytes: Int64(13.9 * Double(GB)), category: .other, fileCount: 546_062),
                ]),
            ScanNode(
                name: "Library", path: "/Library", sizeBytes: 38 * GB,
                category: .caches, fileCount: 142_391, children: [
                    ScanNode(name: "Caches", path: "~/Library/Caches", sizeBytes: Int64(24.1 * Double(GB)), category: .caches, fileCount: 89_234),
                    ScanNode(name: "Application Support", path: "~/Library/Application Support", sizeBytes: Int64(6.2 * Double(GB)), category: .applications, fileCount: 18_204),
                    ScanNode(name: "Logs", path: "~/Library/Logs", sizeBytes: Int64(2.3 * Double(GB)), category: .logs, fileCount: 12_891),
                    ScanNode(name: "WebKit", path: "~/Library/WebKit", sizeBytes: Int64(2.1 * Double(GB)), category: .other, fileCount: 9_412),
                    ScanNode(name: "HTTPStorages", path: "~/Library/HTTPStorages", sizeBytes: Int64(1.8 * Double(GB)), category: .caches, fileCount: 7_234),
                    ScanNode(name: "Saved App State", path: "~/Library/Saved Application State", sizeBytes: Int64(1.2 * Double(GB)), category: .other, fileCount: 3_891),
                    ScanNode(name: "Other", path: "~/Library", sizeBytes: Int64(0.3 * Double(GB)), category: .other, fileCount: 1_525),
                ]),
            ScanNode(
                name: "Other", path: "/private", sizeBytes: 36 * GB,
                category: .other, fileCount: 58_307),
        ])

    static var topLevel: [ScanNode] { root.children }
}
