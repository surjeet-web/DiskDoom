import Foundation
import AppKit

// MARK: - Flat file record (Sendable; feeds duplicates/large/old finders)

struct ScannedRecord: Sendable {
    let path: String
    let bytes: Int64
    let physical: Int64
    let modified: Date
    let isDirectory: Bool
    let category: NodeCategory
}

struct ScanOptions: Sendable {
    var includeHidden = true
    var followSymlinks = false
    var maxDepth = 0 // 0 = unlimited
    var excludedPaths: [String] = []
    var maxFiles = 1_000_000
    var maxChildrenPerDir = 300
}

struct ScanResult: Sendable {
    let root: ScanNode
    let records: [ScannedRecord]
    let skipped: [String]
    let elapsed: Double
    let isPartial: Bool
}

// MARK: - Real filesystem scanner (bounded, cancellable, error-recovering)

final class RealScanEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentPath = ""
    @Published private(set) var filesFound = 0

    private var installedIDs: Set<String> = []

    /// Walk root and build a sized tree + flat records. Skips unreadable dirs
    /// (logs them into `skipped`) instead of failing — partial results survive.
    func scan(root: URL, label: String, options: ScanOptions) async -> ScanResult {
        let start = Date()
        await publish(progress: 0, path: root.path, files: 0)
        collectInstalledIDs()
        var records: [ScannedRecord] = []
        records.reserveCapacity(50_000)
        var skipped: [String] = []
        var counter = 0
        var dirCount = 0
        var visited = Set<DevIno>()
        let node = scanDir(
            url: root, name: label, path: root.path, depth: 0,
            options: options, records: &records, skipped: &skipped,
            counter: &counter, dirCount: &dirCount, visited: &visited,
            progress: { [weak self] currentDir, count in
                guard let self else { return }
                // Copy into Sendable locals before hopping threads.
                let dir: String = currentDir
                let files: Int = count
                Task { @MainActor in
                    self.progress = min(0.99, Double(files) / 200_000.0)
                    self.currentPath = dir
                    self.filesFound = files
                }
            })
        let elapsed = Date().timeIntervalSince(start)
        let finalNode = node ?? ScanNode(name: label, path: root.path, sizeBytes: 0, category: .other, fileCount: 0)
        await publish(progress: 1, path: "", files: counter)
        return ScanResult(root: finalNode, records: records, skipped: skipped, elapsed: elapsed, isPartial: !skipped.isEmpty)
    }

    /// (device, inode) of visited directories — kills symlink cycles,
    /// firmlink double-walks (/, /System/Volumes/Data, /Users → same inodes),
    /// and any other hardlinked directory loops.
    private struct DevIno: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    // MARK: Recursive walk

    private func scanDir(
        url: URL, name: String, path: String, depth: Int,
        options: ScanOptions, records: inout [ScannedRecord], skipped: inout [String],
        counter: inout Int, dirCount: inout Int, visited: inout Set<DevIno>,
        progress: (String, Int) -> Void
    ) -> ScanNode? {
        if Task.isCancelled { return nil }
        if options.maxDepth > 0 && depth > options.maxDepth { return nil }
        let fm = FileManager.default
        var resourceValues: URLResourceValues?
        do {
            resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        } catch {
            skipped.append("\(path): \(error.localizedDescription)")
            return nil
        }
        let isSymlink = resourceValues?.isSymbolicLink ?? false
        if isSymlink && !options.followSymlinks { return nil }
        let isDir = (resourceValues?.isDirectory ?? false) || isSymlink
        if !isDir {
            // Single file target.
            let meta = fileMeta(path: path)
            counter += 1
            if counter % 2000 == 0 { progress(path, counter) }
            if records.count < options.maxFiles {
                records.append(ScannedRecord(path: path, bytes: meta.logical, physical: meta.physical, modified: meta.mtime, isDirectory: false, category: classify(path: path)))
            }
            return ScanNode(name: name, path: path, sizeBytes: meta.logical, category: classify(path: path), fileCount: 1, modified: meta.mtime, physicalBytes: meta.physical)
        }
        // Directory: cycle guard first (firmlinks/symlinked dirs share inodes).
        var st = stat()
        guard stat(path, &st) == 0 else {
            skipped.append("\(path): Operation not permitted")
            return nil
        }
        let identity = DevIno(dev: st.st_dev, ino: st.st_ino)
        guard visited.insert(identity).inserted else { return nil } // already walked
        dirCount += 1
        if dirCount % 25 == 0 { progress(path, counter) }
        // Directory: enumerate children.
        var dirOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden { dirOptions.insert(.skipsHiddenFiles) }
        guard let children = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: dirOptions)
        else {
            skipped.append("\(path): Operation not permitted")
            return nil
        }
        var nodes: [ScanNode] = []
        var total: Int64 = 0
        var fileCount = 0
        for child in children {
            if Task.isCancelled { break }
            let childPath = child.path
            if options.excludedPaths.contains(where: { childPath.hasPrefix($0) }) { continue }
            if let childNode = scanDir(url: child, name: child.lastPathComponent, path: childPath, depth: depth + 1, options: options, records: &records, skipped: &skipped, counter: &counter, dirCount: &dirCount, visited: &visited, progress: progress) {
                nodes.append(childNode)
                total += childNode.sizeBytes
                fileCount += childNode.fileCount
            }
        }
        // Cap breadth: keep largest, aggregate the tail into "Other".
        nodes.sort { $0.sizeBytes > $1.sizeBytes }
        if nodes.count > options.maxChildrenPerDir {
            let tail = nodes[options.maxChildrenPerDir...]
            let tailBytes = tail.reduce(0) { $0 + $1.sizeBytes }
            let tailFiles = tail.reduce(0) { $0 + $1.fileCount }
            nodes = Array(nodes.prefix(options.maxChildrenPerDir))
            nodes.append(ScanNode(name: "Other (\(tail.count) items)", path: path, sizeBytes: tailBytes, category: .other, fileCount: tailFiles))
        }
        let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return ScanNode(name: name, path: path, sizeBytes: total, category: classify(path: path), fileCount: fileCount, children: nodes, modified: mtime, physicalBytes: total)
    }

    // MARK: Metadata + classification

    private func fileMeta(path: String) -> (logical: Int64, physical: Int64, mtime: Date) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return (0, 0, Date.distantPast) }
        let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        return (Int64(st.st_size), Int64(st.st_blocks) * 512, mtime)
    }

    private func classify(path: String) -> NodeCategory {
        let lower = path.lowercased()
        if lower.hasSuffix(".app") || lower.contains("/applications/") { return .applications }
        if lower.contains("/caches/") || lower.contains("httpstorage") { return .caches }
        if lower.contains("/logs/") || lower.contains("/log/") { return .logs }
        if isStaleArtifact(path: path) { return .stale }
        if lower.hasPrefix("/system/") || lower.hasPrefix("/library/") || lower.hasPrefix("/private/") || lower.hasPrefix("/bin") || lower.hasPrefix("/sbin") || lower.hasPrefix("/usr/") { return .system }
        return isUserPath(path) ? .userData : .other
    }

    private func isUserPath(_ path: String) -> Bool {
        path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/")
    }

    private func isStaleArtifact(path: String) -> Bool {
        // Library artifact whose owner name matches no installed bundle ID.
        let markers = ["Caches", "Application Support", "Preferences", "HTTPStorages", "Containers", "Group Containers", "Saved Application State"]
        let components = path.split(separator: "/").map(String.init)
        for marker in markers {
            if let i = components.lastIndex(of: marker), i + 1 < components.count {
                let owner = components[i + 1].replacingOccurrences(of: ".plist", with: "")
                if !owner.isEmpty && !installedIDs.contains(where: { $0.localizedCaseInsensitiveContains(owner) || owner.localizedCaseInsensitiveContains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private func collectInstalledIDs() {
        var ids = Set<String>()
        let fm = FileManager.default
        for dir in ["/Applications", fm.homeDirectoryForCurrentUser.path + "/Applications"] {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let url = URL(fileURLWithPath: "\(dir)/\(app)")
                if let id = Bundle(url: url)?.bundleIdentifier {
                    ids.insert(id)
                } else {
                    ids.insert((app as NSString).deletingPathExtension)
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { ids.insert(id) }
        }
        installedIDs = ids
    }

    @MainActor
    private func publish(progress: Double, path: String, files: Int) {
        self.progress = progress
        self.currentPath = path
        self.filesFound = files
    }
}
