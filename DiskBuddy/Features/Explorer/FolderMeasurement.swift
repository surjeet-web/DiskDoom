import Foundation

// MARK: - Measurement model (thresholds are NOT part of the cache key:
// measure once completely, filter/sort in the view layer)

struct FolderMeasurement: Sendable, Codable, Hashable {
    let path: String
    let totalSize: Int64
    let totalFileCount: Int
    let totalFolderCount: Int
    let children: [FolderChild]
    let measuredAt: Date
    let includesHidden: Bool
    let measurementVersion: Int

    static let currentMeasurementVersion = 1
}

struct FolderChild: Identifiable, Sendable, Codable, Hashable {
    var id: String { path }

    let path: String
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isPackage: Bool
    let isSymlink: Bool

    let fileCount: Int?
    let folderCount: Int?
    let childCount: Int?

    let modified: Date?
    let fileExtension: String?
}

struct FolderMeasurementCacheKey: Hashable, Sendable {
    let path: String
    let includesHidden: Bool
    let measurementVersion: Int

    init(path: String, includesHidden: Bool, measurementVersion: Int = FolderMeasurement.currentMeasurementVersion) {
        self.path = path
        self.includesHidden = includesHidden
        self.measurementVersion = measurementVersion
    }
}
