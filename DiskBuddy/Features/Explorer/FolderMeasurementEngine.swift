import Foundation

// MARK: - Single-traversal folder measurement (actor; memory cache; never follows symlinks)
//
// One recursive walk measures the selected directory — no `du` per child.
// Packages are leaves; symlinks are counted, never followed (no cycles,
// no double counting, no escaping the selected tree). Sizes are LOGICAL
// (totalFileSize); allocated-size tracking belongs in a separate field.

actor FolderMeasurementEngine {
    static let shared = FolderMeasurementEngine()
    static let measurementTTL: TimeInterval = 60
    static let cacheLimit = 64

    private let perform: @Sendable (String, Bool) throws -> FolderMeasurement
    private let canRead: @Sendable (String) -> Bool

    init(perform: (@Sendable (String, Bool) throws -> FolderMeasurement)? = nil,
         canRead: @escaping @Sendable (String) -> Bool = { !FileManager.default.fileExists(atPath: $0) || FileManager.default.isReadableFile(atPath: $0) }) {
        self.perform = perform ?? { try Self.performMeasurement(path: $0, includeHidden: $1) }
        self.canRead = canRead
    }

    private struct DirectoryAccumulator {
        var totalSize: Int64 = 0
        var totalFileCount: Int = 0
        var totalFolderCount: Int = 0
        /// WHY: without this, a permission-denied subtree returned an empty
        /// accumulator and its 0 bytes were merged into a confident total.
        var unreadableCount: Int = 0
    }

    private var cache: [FolderMeasurementCacheKey: FolderMeasurement] = [:]
    private var inProgress: [FolderMeasurementCacheKey: (id: UUID, task: Task<FolderMeasurement, Error>)] = [:]

    func measure(path: String, includeHidden: Bool = false, forceRefresh: Bool = false, now: Date = Date()) async throws -> FolderMeasurement {
        let canonical = canonicalPath(path)
        let key = FolderMeasurementCacheKey(path: canonical, includesHidden: includeHidden)
        cache = cache.filter { $0.value.evidence(now: now).availableValue != nil && !$0.value.isPartial }
        guard canRead(canonical) else {
            cache[key] = nil
            throw ExplorerError.accessDenied(canonical)
        }
        if !forceRefresh, var cached = cache[key] {
            cached.measurementSource = "Memory cache · filesystem traversal (logical bytes)"
            return cached
        }
        if !forceRefresh, let existing = inProgress[key] {
            let result = try await existing.task.value
            try Task.checkCancellation()
            return result
        }
        cache[key] = nil
        let perform = self.perform
        let requestID = UUID()

        let task = Task.detached(priority: .userInitiated) {
            try perform(canonical, includeHidden)
        }
        inProgress[key] = (requestID, task)
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard canRead(canonical) else {
                throw ExplorerError.accessDenied(canonical)
            }
            guard inProgress[key]?.id == requestID else { return result }
            inProgress[key] = nil
            if !result.isPartial {
                cache[key] = result
                if cache.count > Self.cacheLimit,
                   let oldest = cache.min(by: { $0.value.measuredAt < $1.value.measuredAt })?.key {
                    cache[oldest] = nil
                }
            }
            return result
        } catch {
            if inProgress[key]?.id == requestID {
                inProgress[key] = nil
                cache[key] = nil
            }
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
        var totalUnreadable = 0
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
            let childPath = childURL.standardizedFileURL.path
            let ext = childURL.pathExtension
            let extensionValue: String? = ext.isEmpty ? nil : ext
            let values: URLResourceValues
            do {
                values = try childURL.resourceValues(forKeys: keys)
            } catch {
                // WHY: metadata for this child could not be read (permission
                // denied or it vanished mid-walk). Dropping the row entirely
                // hid the gap and let the parent total claim completeness —
                // keep a row so it renders a lock + "Permission denied".
                totalUnreadable += 1
                children.append(FolderChild(
                    path: childPath, name: childURL.lastPathComponent, size: 0,
                    isDirectory: false, isPackage: false, isSymlink: false,
                    fileCount: nil, folderCount: nil, childCount: nil,
                    modified: nil, fileExtension: extensionValue,
                    isUnreadable: true))
                continue
            }
            let childIsDirectory = values.isDirectory ?? false
            let childIsSymlink = values.isSymbolicLink ?? false
            let childIsPackage = values.isPackage ?? false
            let childName = values.name ?? childURL.lastPathComponent
            guard values.isDirectory != nil, (!childIsSymlink || values.fileSize != nil),
                  (childIsDirectory && !childIsSymlink && !childIsPackage) || values.totalFileSize != nil || values.fileSize != nil else {
                totalUnreadable += 1
                children.append(FolderChild(
                    path: childPath, name: childName, size: 0,
                    isDirectory: childIsDirectory, isPackage: childIsPackage, isSymlink: childIsSymlink,
                    fileCount: nil, folderCount: nil, childCount: nil,
                    modified: values.contentModificationDate, fileExtension: extensionValue,
                    isUnreadable: true))
                continue
            }

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
                let result = try measureDirectoryRecursively(rootURL: childURL, includeHidden: includeHidden, resourceKeys: keys)
                totalSize += result.totalSize
                totalFiles += result.totalFileCount
                totalFolders += result.totalFolderCount + 1
                totalUnreadable += result.unreadableCount
                let immediate = (try? fm.contentsOfDirectory(
                    at: childURL, includingPropertiesForKeys: nil,
                    options: includeHidden ? [] : [.skipsHiddenFiles]))?.count
                children.append(FolderChild(
                    path: childPath, name: childName, size: result.totalSize,
                    isDirectory: true, isPackage: false, isSymlink: false,
                    fileCount: result.totalFileCount, folderCount: result.totalFolderCount,
                    childCount: immediate,
                    modified: values.contentModificationDate, fileExtension: extensionValue,
                    // WHY: nothing inside was readable, so the 0 bytes above are
                    // an absence of data, not a measurement — the row must say so.
                    isUnreadable: result.unreadableCount > 0 && result.totalSize == 0,
                    isPartial: result.unreadableCount > 0))
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
            measurementVersion: FolderMeasurement.currentMeasurementVersion,
            unreadableFolderCount: totalUnreadable)
    }

    private static func measureDirectoryRecursively(rootURL: URL, includeHidden: Bool, resourceKeys: Set<URLResourceKey>) throws -> DirectoryAccumulator {
        var accumulator = DirectoryAccumulator()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: Array(resourceKeys),
            options: includeHidden ? [] : [.skipsHiddenFiles])
        else {
            // WHY: enumeration failed (typically TCC: ~/Library/Mail without
            // Full Disk Access). Returning a 0-byte accumulator here made the
            // unreadable folder look measured at exactly 0 and the total look
            // complete — count it so the UI can label the total a lower bound.
            accumulator.unreadableCount += 1
            return accumulator
        }

        for url in contents {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                // WHY: this child's metadata is unreadable — skipping it with
                // `continue` silently dropped its bytes from the total. Count
                // it (the row is rendered with a lock instead of a size).
                accumulator.unreadableCount += 1
                continue
            }
            let isDirectory = values.isDirectory ?? false
            let isSymlink = values.isSymbolicLink ?? false
            let isPackage = values.isPackage ?? false
            guard values.isDirectory != nil, (!isSymlink || values.fileSize != nil),
                  (isDirectory && !isSymlink && !isPackage) || values.totalFileSize != nil || values.fileSize != nil else {
                accumulator.unreadableCount += 1
                continue
            }
            if isSymlink {
                accumulator.totalSize += max(0, Int64(values.fileSize ?? 0))
                accumulator.totalFileCount += 1
                continue
            }
            if isDirectory && !isPackage {
                let nested = try measureDirectoryRecursively(rootURL: url, includeHidden: includeHidden, resourceKeys: resourceKeys)
                accumulator.totalSize += nested.totalSize
                accumulator.totalFileCount += nested.totalFileCount
                accumulator.totalFolderCount += nested.totalFolderCount + 1
                accumulator.unreadableCount += nested.unreadableCount
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
