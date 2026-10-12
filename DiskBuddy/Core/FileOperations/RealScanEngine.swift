import Foundation
import AppKit

// MARK: - Flat file record (Sendable; feeds duplicates/large/old finders)

struct ScannedRecord: Sendable, Codable {
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
    var collapseSmartLeaves = true
    var maxNodes = 400_000 // scan budget: files walked before collapsing rest
    var maxScanSeconds = 240.0 // scan budget: wall-clock cap
}

// MARK: - Directory classification: normal vs collapsed vs package
//
// Smart leaves are COLLAPSED, not inaccessible: the aggregate (size + file
// count + reason) is measured with a lightweight lstat walk — no per-file
// records, no tree nodes, no DB rows. Double-click expands on demand.
// Cheap signals only (name/path/package bit); never measure-to-decide.

enum DirectoryKind: Sendable {
    case normal
    case package
    case smartLeaf(reason: String)

    private static let sourceControl: Set<String> = [".git", ".svn", ".hg", ".jj"]
    private static let dependencyStores: Set<String> = [
        "node_modules", "bower_components", "vendor", ".pub-cache", ".nuget",
        "packages", "Pods", "Carthage", ".cargo", ".m2", ".gradle", ".npm",
        ".yarn", ".pnpm-store",
    ]
    private static let buildArtifacts: Set<String> = [
        "DerivedData", "Build", "BuildProductsPath", "dist", "build", "out",
        "coverage", "target", "obj", "bin", ".next", ".nuxt", ".output",
        ".svelte-kit", ".astro", ".turbo", ".parcel-cache", ".cache",
        "SourcePackages", "Index.noindex", "ModuleCache.noindex", "xcuserdata",
        ".build", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        ".tox", ".terraform", ".terraform.d", "zig-cache", ".zig-cache",
        ".venv", "venv", "env",
    ]
    private static let cacheDirs: Set<String> = [
        "Caches", "Cache", "Code Cache", "GPUCache", "DawnCache", "Crashpad",
        "Service Worker",
    ]
    private static let vmDirs: Set<String> = [
        "Virtual Machines", "Parallels", "VMware", "VMware Fusion", "UTM",
    ]

    static func classify(name: String, path: String, isPackage: Bool) -> DirectoryKind {
        if isPackage { return .package }
        if path.contains("com.docker.docker") || path.contains("group.com.docker") {
            return .smartLeaf(reason: "Virtualized container storage")
        }
        if sourceControl.contains(name) {
            return .smartLeaf(reason: "Version control data — drill in to index")
        }
        if dependencyStores.contains(name) {
            return .smartLeaf(reason: "Dependency store — drill in to index")
        }
        if buildArtifacts.contains(name) {
            return .smartLeaf(reason: "Build output — drill in to index")
        }
        if cacheDirs.contains(name) {
            return .smartLeaf(reason: "Cache data — safe to clean")
        }
        if vmDirs.contains(name) {
            return .smartLeaf(reason: "Virtual machine storage")
        }
        return .normal
    }
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
        var budgetHit = false
        let startedAt = Date()
        let node = scanDir(
            url: root, name: label, path: root.path, depth: 0,
            options: options, records: &records, skipped: &skipped,
            counter: &counter, dirCount: &dirCount, visited: &visited,
            budgetHit: &budgetHit, startedAt: startedAt,
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
        budgetHit: inout Bool, startedAt: Date,
        progress: (String, Int) -> Void
    ) -> ScanNode? {
        if Task.isCancelled { return nil }
        if options.maxDepth > 0 && depth > options.maxDepth { return nil }
        // Scan budget: stop descending once hit; the scan reports partial
        // instead of grinding forever on pathological trees.
        if counter > options.maxNodes || Date().timeIntervalSince(startedAt) > options.maxScanSeconds {
            if !budgetHit {
                budgetHit = true
                skipped.append("Scan budget reached at \(path) — deeper items omitted, drill in to measure them directly")
            }
            return nil
        }
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
        // Packages are leaves in the tree, but they must still be *measured*
        // correctly. `URLResourceValues.totalFileSizeKey` returns nil for any
        // directory, so the old lookup reported every application bundle as
        // 0 bytes (verified: Xcode.app = 5.5 GB measured as nil -> 0).
        // Walk the bundle instead, including nested bundles, so Xcode.app
        // reports ~5.5 GB rather than just its wrapper.
        let isPackage = resourceValues?.isPackage ?? false
        if isPackage {
            let measured = measurePackage(url: url, options: options,
                                          skipped: &skipped, startedAt: startedAt)
            counter += 1
            return ScanNode(name: name, path: path, sizeBytes: measured.bytes,
                            category: .applications, fileCount: measured.files,
                            modified: fileMeta(path: path).mtime,
                            physicalBytes: measured.bytes,
                            isCollapsed: true,
                            collapseReason: "Application bundle — double-click to index")
        }
        // Smart leaves: aggregate totals with a record-free lstat walk.
        if options.collapseSmartLeaves, depth > 0 {
            switch DirectoryKind.classify(name: name, path: path, isPackage: false) {
            case .smartLeaf(let reason):
                let aggregate = aggregateSubtree(
                    url: url, options: options, visited: &visited,
                    counter: &counter, skipped: &skipped,
                    budgetHit: &budgetHit, startedAt: startedAt, progress: progress)
                return ScanNode(
                    name: name, path: path, sizeBytes: aggregate.bytes,
                    category: classify(path: path), fileCount: aggregate.files,
                    modified: fileMeta(path: path).mtime, physicalBytes: aggregate.bytes,
                    isCollapsed: true, collapseReason: reason)
            case .package, .normal:
                break
            }
        }
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
            if options.excludedPaths.contains(where: { childPath == $0 || childPath.hasPrefix($0 + "/") }) { continue }
            if let childNode = scanDir(url: child, name: child.lastPathComponent, path: childPath, depth: depth + 1, options: options, records: &records, skipped: &skipped, counter: &counter, dirCount: &dirCount, visited: &visited, budgetHit: &budgetHit, startedAt: startedAt, progress: progress) {
                nodes.append(childNode)
                total = Self.saturatingAdd(total, childNode.sizeBytes)
                fileCount += childNode.fileCount
            }
        }
        // Cap breadth: keep largest, aggregate the tail into "Other".
        nodes.sort { $0.sizeBytes > $1.sizeBytes }
        if nodes.count > options.maxChildrenPerDir {
            let tail = nodes[options.maxChildrenPerDir...]
            let tailBytes = tail.reduce(Int64(0)) { Self.saturatingAdd($0, $1.sizeBytes) }
            let tailFiles = tail.reduce(0) { $0 + $1.fileCount }
            nodes = Array(nodes.prefix(options.maxChildrenPerDir))
            // This node represents a *tail*, not a real directory. It must
            // never carry the parent's `path` for destructive actions —
            // staging it used to trash the entire parent folder while the UI
            // showed only the tail's size.
            nodes.append(ScanNode(
                name: "Other (\(tail.count) items)", path: "",
                sizeBytes: tailBytes, category: .other, fileCount: tailFiles,
                collapseReason: "\(tail.count) aggregated items — not a real folder",
                isSyntheticAggregate: true))
        }
        let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return ScanNode(name: name, path: path, sizeBytes: total, category: classify(path: path), fileCount: fileCount, children: nodes, modified: mtime, physicalBytes: total)
    }

    // MARK: Metadata + classification

    /// Lightweight aggregate walk for smart leaves: lstat totals only —
    /// no ScanNode allocations, no records, no DB rows. Shares the visited
    /// set (no double counting) and honors cancellation + budget.
    private func aggregateSubtree(
        url: URL, options: ScanOptions, visited: inout Set<DevIno>,
        counter: inout Int, skipped: inout [String],
        budgetHit: inout Bool, startedAt: Date,
        progress: (String, Int) -> Void
    ) -> (bytes: Int64, files: Int) {
        if Task.isCancelled { return (0, 0) }
        if counter > options.maxNodes || Date().timeIntervalSince(startedAt) > options.maxScanSeconds {
            if !budgetHit {
                budgetHit = true
                skipped.append("Scan budget reached inside \(url.path) — drill in to measure it directly")
            }
            return (0, 0)
        }
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return (0, 0) }
        if (st.st_mode & S_IFMT) != S_IFDIR {
            counter += 1
            return (Int64(st.st_size), 1)
        }
        // No visited-set check here: the caller already inserted this
        // directory, and symlinks are never descended (lstat above), so
        // cycles are impossible. (The redundant check used to reject the
        // entry inode and zero out every smart leaf.) Still record
        // descendants so the rest of the walk dedups against them.
        _ = visited.insert(DevIno(dev: st.st_dev, ino: st.st_ino))
        var dirOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHidden { dirOptions.insert(.skipsHiddenFiles) }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: dirOptions)
        else { return (0, 0) }
        var bytes: Int64 = 0
        var files = 0
        for child in children {
            if Task.isCancelled { break }
            let sub = aggregateSubtree(
                url: child, options: options, visited: &visited,
                counter: &counter, skipped: &skipped,
                budgetHit: &budgetHit, startedAt: startedAt, progress: progress)
            bytes = Self.saturatingAdd(bytes, sub.bytes)
            files += sub.files
            if files % 5000 == 0 { progress(url.path, counter) }
        }
        return (bytes, files)
    }

    /// On-demand expansion of a collapsed node: measures just that subtree
    /// (smart leaves stay on inside it, depth-capped) for drill-in.
    func expandSubtree(path: String, options: ScanOptions) -> (children: [ScanNode], records: [ScannedRecord]) {
        var records: [ScannedRecord] = []
        var skipped: [String] = []
        var counter = 0
        var dirCount = 0
        var visited = Set<DevIno>()
        var budgetHit = false
        var opts = options
        opts.maxDepth = 4
        let url = URL(fileURLWithPath: path)
        guard let node = scanDir(
            url: url, name: url.lastPathComponent, path: path, depth: 0,
            options: opts, records: &records, skipped: &skipped,
            counter: &counter, dirCount: &dirCount, visited: &visited,
            budgetHit: &budgetHit, startedAt: Date(),
            progress: { _, _ in })
        else { return ([], []) }
        return (node.children, records)
    }

    /// Logical size + file count for a package bundle (`.app`, `.framework`,
    /// `.prefPane`, `.kext`, …).
    ///
    /// Uses an explicit work stack rather than recursion so a pathological
    /// bundle cannot overflow the cooperative-pool stack, and saturating
    /// arithmetic so a sparse file reporting `st_size == Int64.max` cannot
    /// trap the process. Deliberately emits no `ScannedRecord`s: indexing
    /// every file inside every app would blow up the record store for no
    /// benefit, since a bundle is presented as a single leaf.
    private func measurePackage(
        url: URL, options: ScanOptions, skipped: inout [String], startedAt: Date
    ) -> (bytes: Int64, files: Int) {
        var bytes: Int64 = 0
        var files = 0
        var stack: [URL] = [url]
        var visitedEntries = 0
        var truncated = false
        // Bounded by time and entry count so one huge bundle cannot consume
        // the whole scan budget without saying so.
        let entryCap = 400_000
        while let next = stack.popLast() {
            if Task.isCancelled { truncated = true; break }
            visitedEntries += 1
            if visitedEntries > entryCap
                || Date().timeIntervalSince(startedAt) > options.maxScanSeconds {
                truncated = true
                break
            }
            var st = stat()
            guard lstat(next.path, &st) == 0 else { continue }
            if (st.st_mode & S_IFMT) == S_IFDIR {
                // NOTE: deliberately no `.skipsPackageDescendants` here —
                // skipping it would miss the nested frameworks/helpers that
                // make up most of a modern app bundle's size.
                var opts: FileManager.DirectoryEnumerationOptions = []
                if !options.includeHidden { opts.insert(.skipsHiddenFiles) }
                guard let kids = try? FileManager.default.contentsOfDirectory(
                    at: next, includingPropertiesForKeys: nil, options: opts) else { continue }
                stack.append(contentsOf: kids)
            } else {
                bytes = Self.saturatingAdd(bytes, Int64(st.st_size))
                files += 1
            }
        }
        if truncated {
            skipped.append("\(url.lastPathComponent): bundle measurement stopped early — size is a lower bound")
        }
        return (bytes, files)
    }

    /// Overflow-safe addition. Sparse files and hostile/broken metadata can
    /// report sizes near `Int64.max`; a plain `+=` over a large tree traps
    /// and terminates the app.
    @inline(__always)
    static func saturatingAdd(_ a: Int64, _ b: Int64) -> Int64 {
        let (sum, overflow) = a.addingReportingOverflow(b)
        guard overflow else { return sum }
        return b > 0 ? Int64.max : Int64.min
    }

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
