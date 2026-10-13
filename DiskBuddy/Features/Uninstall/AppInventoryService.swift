import Foundation
import AppKit

// MARK: - Real app inventory: bundles + matched Library artifacts + stale leftovers
//
// No mocks: enumerates /Applications + ~/Applications (+ running apps),
// measures bundles via totalFileSize, matches artifacts by bundle ID/name
// across ~/Library, and flags owners with no installed bundle as stale.
// Runs in a cancellable background Task; progress published for the UI.

struct AppArtifactInfo: Hashable, Sendable, Codable {
    let path: String
    let bytes: Int64
    let kind: String // Caches, Preferences, Application Support, …
}

@MainActor
final class AppInventoryService: ObservableObject, @unchecked Sendable {
    // Main-confined publishes; heavy work in background Task with hops.
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedCount = 0
    @Published private(set) var sharedArtifactOwners: Set<String> = []
    private var task: Task<Void, Never>?

    nonisolated private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DiskBuddy/app-inventory.json")
    }

    init() {
        // Local-storage-first: hydrate the last scan instantly, then the UI
        // can trigger a fresh scan whenever it wants.
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode([AppEntry].self, from: data) {
            apps = cached
        }
    }

    func scan() {
        task?.cancel()
        isScanning = true
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isScanning = true
                self.scannedCount = 0
            }
            let worker = Task.detached { Self.scanSync(report: { _ in }) }
            let found = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.apps = found.apps.sorted { $0.totalBytes > $1.totalBytes }
                self.sharedArtifactOwners = found.shared
                self.isScanning = false
            }
            // Persist for instant next launch.
            let toSave = found.apps
            Task.detached {
                if let data = try? JSONEncoder().encode(toSave) {
                    try? FileManager.default.createDirectory(
                        at: Self.cacheURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true)
                    try? data.write(to: Self.cacheURL, options: .atomic)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    // MARK: Synchronous scan (runs detached)

    private struct ScanOutput: Sendable {
        let apps: [AppEntry]
        let shared: Set<String>
    }

    /// True for macOS components that must never be uninstalled or staged.
    /// Blocks /System/*, /Applications/Utilities, and the OS's own support
    /// directories, so the UI can't invite the user to trash Safari.
    nonisolated static func isSystemBundle(_ path: String) -> Bool {
        let p = path.hasSuffix("/") ? String(path.dropLast()) : path
        if p.hasPrefix("/System/") || p.hasPrefix("/System") { return true }
        if p == "/Applications/Utilities" || p.hasPrefix("/Applications/Utilities/") { return true }
        if p.hasPrefix("/Library/Apple/") || p.hasPrefix("/Library/Application Support/Apple/") { return true }
        // Anything inside the OS volume's read-only system area.
        if p.hasPrefix("/private/var/db/") || p.hasPrefix("/private/var/vm/") { return true }
        return false
    }

    nonisolated private static func scanSync(report: (Int) -> Void) -> ScanOutput {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let library = "\(home)/Library"

        // 1. Installed bundles.
        var bundles: [(url: URL, id: String, name: String, version: String, installed: Date?)] = []
        var seenPaths = Set<String>()
        var appDirs = ["/Applications", "\(home)/Applications"]
        for running in NSWorkspace.shared.runningApplications {
            if let url = running.bundleURL, url.pathExtension == "app" {
                appDirs.append(url.deletingLastPathComponent().path)
            }
        }
        for dir in Set(appDirs) {
            if Task.isCancelled { break }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                if Task.isCancelled { break }
                let url = URL(fileURLWithPath: "\(dir)/\(name)")
                // macOS component: never offer to uninstall, never stage.
                // These come from /System/Applications & friends via the
                // running-apps sweep above.
                if Self.isSystemBundle(url.path) { continue }
                let bundle = Bundle(url: url)
                let id = bundle?.bundleIdentifier ?? (name as NSString).deletingPathExtension
                // De-duplicate on PATH, not bundle ID: two copies of the same
                // app (/Applications/Slack.app and ~/Applications/Slack.app)
                // previously collapsed into one, so the second copy was
                // invisible and un-uninstallable.
                guard seenPaths.insert(url.path).inserted else { continue }
                let version = (bundle?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
                let installed = (try? fm.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
                bundles.append((url, id, (name as NSString).deletingPathExtension, version, installed))
            }
        }

        // 2. Artifacts per bundle.
        let libDirs: [(dir: String, kind: String)] = [
            ("Caches", "Caches"), ("Application Support", "Application Support"),
            ("Preferences", "Preferences"), ("HTTPStorages", "HTTPStorages"),
            ("Saved Application State", "Saved State"), ("WebKit", "WebKit"),
            ("Containers", "Container"), ("Group Containers", "Group Container"),
            ("LaunchAgents", "Launch Agent"), ("Logs", "Logs"),
        ]
        var apps: [AppEntry] = []
        var ownerUseCount: [String: Int] = [:]
        var teamSharedArtifactOwners: Set<String> = []
        var count = 0
        for bundle in bundles {
            if Task.isCancelled { break }
            count += 1
            report(count)
            let bundleBytes = totalSize(of: bundle.url.path)
            var artifacts: [AppArtifactInfo] = []
            let baseName = bundle.name
            for (dir, kind) in libDirs {
                if Task.isCancelled { break }
                let candidates = artifactCandidates(bundleID: bundle.id, appName: baseName, dir: dir, library: library)
                for path in candidates {
                    let bytes = totalSize(of: path)
                    guard bytes > 0 else { continue }
                    artifacts.append(AppArtifactInfo(path: path, bytes: bytes, kind: kind))
                    ownerUseCount[ownerKey(for: path, in: dir)] = (ownerUseCount[ownerKey(for: path, in: dir)] ?? 0) + 1
                    if kind == "Group Container" { teamSharedArtifactOwners.insert(ownerKey(for: path, in: dir)) }
                }
            }
            apps.append(AppEntry(
                name: bundle.name, bundleID: bundle.id, bundlePath: bundle.url.path,
                version: bundle.version, bundleBytes: bundleBytes,
                artifacts: artifacts, installDate: bundle.installed, isStale: false))
        }

        // 3. Stale owners: Library names matching no installed bundle.
        let installedKeys = Set(bundles.map(\.id) + bundles.map(\.name))
        var stale: [AppEntry] = []
        let staleDirs = ["Caches", "Application Support", "Preferences", "HTTPStorages", "Containers", "Saved Application State"]
        outer: for dir in staleDirs {
            if Task.isCancelled { break }
            let dirPath = "\(library)/\(dir)"
            guard let owners = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for owner in owners {
                if Task.isCancelled { break outer }
                if owner.hasPrefix(".") { continue }
                let clean = owner.replacingOccurrences(of: ".plist", with: "")
                // Match on exact bundle ID / name equality, or a dot-prefix
                // relationship. The old bidirectional substring test hid real
                // data: "Google" matched an installed "Google Chrome", so
                // ~/Library/Application Support/Google (often 10+ GB of Chrome,
                // Firefox AND Drive caches) was never offered as stale.
                let ownedByInstalled = installedKeys.contains { key in
                    key.compare(clean, options: .caseInsensitive) == .orderedSame
                        || clean.hasPrefix(key + ".")
                        || key.hasPrefix(clean + ".")
                }
                if ownedByInstalled { continue }
                let path = "\(dirPath)/\(owner)"
                let bytes = totalSize(of: path)
                guard bytes >= 1_000_000 else { continue } // ignore crumbs
                stale.append(AppEntry(
                    name: clean, bundleID: clean, bundlePath: "",
                    version: "—", bundleBytes: 0,
                    artifacts: [AppArtifactInfo(path: path, bytes: bytes, kind: dir)],
                    installDate: nil, isStale: true))
                if stale.count >= 150 { break outer }
            }
        }

        // Shared-by-construction: a `Group Containers` entry is shared with every
        // other app signed by the same Team ID, whether or not those apps are
        // installed here. The old count-based check could only fire when two
        // *installed* apps matched — i.e. exactly never in the dangerous case.
        // Treat those as shared unconditionally so the UI defaults them off.
        var shared = Set(ownerUseCount.filter { $0.value > 1 }.map(\.key))
        shared.formUnion(teamSharedArtifactOwners)
        return ScanOutput(apps: apps + stale.sorted { $0.totalBytes > $1.totalBytes }, shared: shared)
    }

    nonisolated private static func artifactCandidates(bundleID: String, appName: String, dir: String, library: String) -> [String] {
        let base = "\(library)/\(dir)"
        var paths = ["\(base)/\(bundleID)"]
        // Common variants: .plist, .savedState, app-name folders.
        if dir == "Preferences" { paths.append("\(base)/\(bundleID).plist") }
        if dir == "Saved Application State" { paths.append("\(base)/\(bundleID).savedState") }
        if dir == "Application Support" || dir == "Caches" || dir == "Logs" {
            paths.append("\(base)/\(appName)")
        }
        if dir == "Group Containers" {
            // Group containers are named `<TEAMID>.group.<bundleID>` and are
            // SHARED by every app signed with that team — including apps that
            // aren't installed here. The old code matched any owner whose name
            // *contained* the bundle ID's last two components, which swept in
            // sibling apps' containers and broke them on uninstall.
            //
            // Only an exact match on `group.<fullBundleID>` is safe to offer,
            // and even that is flagged as team-shared by the caller.
            if let owners = try? FileManager.default.contentsOfDirectory(atPath: base) {
                let exact = "group.\(bundleID)"
                for owner in owners
                where owner.compare(exact, options: .caseInsensitive) == .orderedSame {
                    paths.append("\(base)/\(owner)")
                }
            }
        }
        let fm = FileManager.default
        return paths.filter { fm.fileExists(atPath: $0) }
    }

    nonisolated private static func ownerKey(for path: String, in dir: String) -> String {
        let comps = path.split(separator: "/").map(String.init)
        if let i = comps.lastIndex(of: dir), i + 1 < comps.count { return comps[i + 1] }
        return path
    }

    /// Logical size of a file or bundle.
    ///
    /// `URLResourceValues.totalFileSizeKey` is **not recursive**: for a
    /// directory (which every `.app` is) it returns the size of the directory
    /// inode, so every bundle reported ~4 KB. That number then flowed into the
    /// "X apps · Y total" header, the Litter Score ratio, and the uninstall
    /// confirmation ("Total to free: 6 KB" for a 2 GB app).
    ///
    /// Uses an explicit work stack (no recursion depth risk), deliberately
    /// without `.skipsPackageDescendants` so nested frameworks/helpers inside
    /// a bundle are counted, and saturating arithmetic so a sparse file cannot
    /// trap the process. Bounded by entry count and time — it runs during
    /// inventory on a background thread and must not stall the app.
    nonisolated static func totalSize(of path: String) -> Int64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) != S_IFDIR { return Int64(st.st_size) }

        var total: Int64 = 0
        var stack: [String] = [path]
        var entries = 0
        let entryCap = 250_000
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while let dir = stack.popLast() {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline { break }
            guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for kid in kids {
                entries += 1
                if entries > entryCap || Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline { return total }
                let child = dir.hasSuffix("/") ? dir + kid : dir + "/" + kid
                var cst = stat()
                guard lstat(child, &cst) == 0 else { continue }
                if (cst.st_mode & S_IFMT) == S_IFDIR {
                    stack.append(child)
                } else {
                    let (sum, overflow) = total.addingReportingOverflow(Int64(cst.st_size))
                    total = overflow ? Int64.max : sum
                }
            }
        }
        return total
    }
}
