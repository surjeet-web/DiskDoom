import Foundation

// MARK: - Single-traversal folder measurement (actor; memory cache; never follows symlinks)
//
// One recursive walk measures the selected directory — no `du` per child.
// Packages are leaves; symlinks are counted, never followed (no cycles,
// no double counting, no escaping the selected tree). Sizes are LOGICAL
// (totalFileSize); allocated-size tracking belongs in a separate field.

actor FolderMeasurementEngine {
    static let shared = FolderMeasurementEngine()

    private struct DirectoryAccumulator {
        var totalSize: Int64 = 0
        var totalFileCount: Int = 0
        var totalFolderCount: Int = 0
    }

    private var cache: [FolderMeasurementCacheKey: FolderMeasurement] = [:]
    private var inProgress: [FolderMeasurementCacheKey: Task<FolderMeasurement, Error>] = [:]

    func measure(path: String, includeHidden: Bool = false, forceRefresh: Bool = false) async throws -> FolderMeasurement {
        let canonical = canonicalPath(path)
        let key = FolderMeasurementCacheKey(path: canonical, includesHidden: includeHidden)
        if !forceRefresh, let cached = cache[key] { return cached }
        if !forceRefresh, let existing = inProgress[key] { return try await existing.value }

        let task = Task.detached(priority: .userInitiated) {
            try Self.performMeasurement(path: canonical, includeHidden: includeHidden)
        }
        inProgress[key] = task
        do {
            let result = try await task.value
            inProgress[key] = nil
            if !Task.isCancelled { cache[key] = result }
            return result
        } catch {
            inProgress[key] = nil
            throw error
        }
    }

    func invalidate(path: String) {
        let canonical = canonicalPath(path)
        cache = cache.filter { !isSameOrDescendant($0.key.path, of: canonical) }
    }

    func invalidateAncestors(of path: String) {
        // Component walk (NOT deletingLastPathComponent in a loop: on "/"
        // Foundation returns "/.." and grows unboundedly — infinite loop).
        let standardized = URL(fileURLWithPath: canonicalPath(path)).standardizedFileURL.path
        var prefixes = ["/"]
        var acc = ""
        for part in standardized.split(separator: "/").map(String.init) {
            acc += "/\(part)"
            prefixes.append(acc)
        }
        let doomed = Set(prefixes)
        cache = cache.filter { !doomed.contains($0.key.path) }
    }

    func invalidateTree(at path: String) {
        invalidate(path: path)
    }

    func invalidateAll() {
        cache.removeAll(keepingCapacity: true)
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isSameOrDescendant(_ path: String, of ancestor: String) -> Bool {
        let normalized = ancestor.hasSuffix("/") ? String(ancestor.dropLast()) : ancestor
        return path == normalized || path.hasPrefix(normalized + "/")
    }

    private static func performMeasurement(path: String, includeHidden: Bool) throws -> FolderMeasurement {
        if Task.isCancelled { throw CancellationError() }
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            throw ExplorerError.pathNotFound(path)
        }
        guard isDirectory.boolValue else {
            throw ExplorerError.notDirectory(path)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .fileSizeKey, .totalFileSizeKey, .contentModificationDateKey, .nameKey,
        ]
        var totalSize: Int64 = 0
        var totalFiles = 0
        var totalFolders = 0
        var children: [FolderChild] = []

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: Array(keys),
                options: includeHidden ? [] : [.skipsHiddenFiles])
        } catch CocoaError.fileReadNoPermission {
            throw ExplorerError.accessDenied(path)
        } catch {
            throw ExplorerError.enumerationFailed(path, error.localizedDescription)
        }

        for childURL in contents {
            try Task.checkCancellation()
            let values: URLResourceValues
            do {
                values = try childURL.resourceValues(forKeys: keys)
            } catch {
                continue
            }
            let childIsDirectory = values.isDirectory ?? false
            let childIsSymlink = values.isSymbolicLink ?? false
            let childIsPackage = values.isPackage ?? false
            let childPath = childURL.standardizedFileURL.path
            let childName = values.name ?? childURL.lastPathComponent
            let ext = childURL.pathExtension
            let extensionValue: String? = ext.isEmpty ? nil : ext

            if childIsSymlink {
                let size = max(0, Int64(values.fileSize ?? 0))
                totalSize += size
                totalFiles += 1
                children.append(FolderChild(
                    path: childPath, name: childName, size: size,
                    isDirectory: childIsDirectory, isPackage: childIsPackage, isSymlink: true,
                    fileCount: nil, folderCount: nil, childCount: nil,
                    modified: values.contentModificationDate, fileExtension: extensionValue))
                continue
            }

            if childIsDirectory && !childIsPackage {
                let result = measureDirectoryRecursively(rootURL: childURL, includeHidden: includeHidden, resourceKeys: keys)
                totalSize += result.totalSize
                totalFiles += result.totalFileCount
                totalFolders += result.totalFolderCount + 1
                let immediate = (try? fm.contentsOfDirectory(
                    at: childURL, includingPropertiesForKeys: nil,
                    options: includeHidden ? [] : [.skipsHiddenFiles]))?.count
                children.append(FolderChild(
                    path: childPath, name: childName, size: result.totalSize,
                    isDirectory: true, isPackage: false, isSymlink: false,
                    fileCount: result.totalFileCount, folderCount: result.totalFolderCount,
                    childCount: immediate,
                    modified: values.contentModificationDate, fileExtension: extensionValue))
            } else {
                let size = max(0, Int64(values.totalFileSize ?? values.fileSize ?? 0))
                totalSize += size
                totalFiles += 1
                children.append(FolderChild(
                    path: childPath, name: childName, size: size,
                    isDirectory: childIsDirectory, isPackage: childIsPackage, isSymlink: false,
                    fileCount: nil, folderCount: nil, childCount: nil,
                    modified: values.contentModificationDate, fileExtension: extensionValue))
            }
        }

        children.sort {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return FolderMeasurement(
            path: path, totalSize: totalSize, totalFileCount: totalFiles,
            totalFolderCount: totalFolders, children: children, measuredAt: Date(),
            includesHidden: includeHidden,
            measurementVersion: FolderMeasurement.currentMeasurementVersion)
    }

    private static func measureDirectoryRecursively(rootURL: URL, includeHidden: Bool, resourceKeys: Set<URLResourceKey>) -> DirectoryAccumulator {
        var accumulator = DirectoryAccumulator()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: Array(resourceKeys),
            options: includeHidden ? [] : [.skipsHiddenFiles])
        else { return accumulator }

        for url in contents {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            let isDirectory = values.isDirectory ?? false
            let isSymlink = values.isSymbolicLink ?? false
            let isPackage = values.isPackage ?? false
            if isSymlink {
                accumulator.totalSize += max(0, Int64(values.fileSize ?? 0))
                accumulator.totalFileCount += 1
                continue
            }
            if isDirectory && !isPackage {
                let nested = measureDirectoryRecursively(rootURL: url, includeHidden: includeHidden, resourceKeys: resourceKeys)
                accumulator.totalSize += nested.totalSize
                accumulator.totalFileCount += nested.totalFileCount
                accumulator.totalFolderCount += nested.totalFolderCount + 1
            } else {
                accumulator.totalSize += max(0, Int64(values.totalFileSize ?? values.fileSize ?? 0))
                accumulator.totalFileCount += 1
            }
        }
        return accumulator
    }
}

enum ExplorerError: LocalizedError, Sendable {
    case pathNotFound(String)
    case notDirectory(String)
    case enumerationFailed(String, String)
    case accessDenied(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .pathNotFound(let path): return "Path not found: \(path)"
        case .notDirectory(let path): return "Not a directory: \(path)"
        case .enumerationFailed(let path, let reason): return "Failed to enumerate \(path): \(reason)"
        case .accessDenied(let path): return "Access denied: \(path)"
        case .invalidPath(let path): return "Invalid path: \(path)"
        }
    }
}
