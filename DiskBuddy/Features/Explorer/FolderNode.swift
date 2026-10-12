import Foundation

// MARK: - Explorer row model (path identity: refreshes never look like new rows)

struct FolderNode: Identifiable, Hashable, Sendable {
    var id: String { path }

    let path: String
    let name: String
    let size: Int64

    let isDirectory: Bool
    let isPackage: Bool
    let isSymlink: Bool

    let childCount: Int?
    let fileCount: Int?
    let modified: Date?
    let fileExtension: String?
    let percentageOfParent: Double

    /// WHY: permission-denied children must not render a measured-looking
    /// "0 B" / "0.0%" — the row shows a lock + "Permission denied" instead.
    var isUnreadable: Bool = false

    var sizeFormatted: String {
        ByteFormatting.format(size)
    }
}
