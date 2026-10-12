import SwiftUI
import Combine
import AppKit

// MARK: - App state: real scan lifecycle, trash, snapshots, notifications, trial

@MainActor
final class AppState: ObservableObject {
    enum OnboardingStep { case welcome, fullDiskAccess, scanTarget }
    enum SidebarTab: String, CaseIterable {
        case explore, duplicates, applications, monitor, snapshots
        case litterScore, forecast, simulator, devCaches, health, budgets, liveFeed
        case lifecycle, provenance, compression, containers, privacy, photos
        case smartClean, storage, folders
        case developer, pro3D, videoEditor
        var title: String {
            switch self {
            case .explore: return "Explore"
            case .duplicates: return "Duplicates"
            case .applications: return "Applications"
            case .monitor: return "Monitor"
            case .snapshots: return "Snapshots"
            case .litterScore: return "Litter Score"
            case .forecast: return "Forecast"
            case .simulator: return "What If?"
            case .devCaches: return "Dev Caches"
            case .health: return "Health"
            case .budgets: return "Budgets"
            case .liveFeed: return "Live Feed"
            case .lifecycle: return "Lifecycle"
            case .provenance: return "Provenance"
            case .compression: return "Compression"
            case .containers: return "Containers"
            case .privacy: return "Privacy"
            case .photos: return "Photos"
            case .smartClean: return "Smart Clean"
            case .storage: return "Storage"
            case .folders: return "Folders"
            case .developer: return "Dev Projects"
            case .pro3D: return "3D & Creative"
            case .videoEditor: return "Video Caches"
            }
        }

        var symbol: String {
            switch self {
            case .explore: return "magnifyingglass"
            case .duplicates: return "doc.on.doc"
            case .applications: return "app.badge"
            case .monitor: return "chart.line.uptrend.xyaxis"
            case .snapshots: return "camera"
            case .litterScore: return "gauge.with.dots.needle.67percent"
            case .forecast: return "chart.line.uptrend.xyaxis"
            case .simulator: return "arrow.triangle.2.circlepath"
            case .devCaches: return "hammer.fill"
            case .health: return "heart.text.square"
            case .budgets: return "gauge.with.dots.needle.33percent"
            case .liveFeed: return "antenna.radiowaves.left.and.right"
            case .lifecycle: return "clock.arrow.circlepath"
            case .provenance: return "magnifyingglass.circle"
            case .compression: return "archivebox.fill"
            case .containers: return "square.grid.3x3.fill.square"
            case .privacy: return "lock.shield.fill"
            case .photos: return "photo.on.rectangle.angled"
            case .smartClean: return "sparkles"
            case .storage: return "internaldrive.fill"
            case .folders: return "folder.fill"
            case .developer: return "hammer.fill"
            case .pro3D: return "cube.fill"
            case .videoEditor: return "film.fill"
            }
        }

        static var primary: [SidebarTab] {
            [.explore, .duplicates, .applications, .monitor, .snapshots]
        }

        static var insights: [SidebarTab] {
            [.smartClean, .litterScore, .forecast, .simulator, .devCaches, .health, .budgets, .liveFeed,
             .lifecycle, .provenance, .compression, .containers, .privacy, .photos, .storage, .folders]
        }

        static var professional: [SidebarTab] {
            [.developer, .pro3D, .videoEditor]
        }
    }

    enum ExploreView: String, CaseIterable {
        case treemap, sunburst, flame, bubbles, mindMap, topSizes, ageMap, folderGrid
        case radial, icicle, treelist, extCloud
        var title: String {
            switch self {
            case .treemap: return "Treemap"
            case .sunburst: return "Sunburst"
            case .flame: return "Flame"
            case .bubbles: return "Bubbles"
            case .mindMap: return "MindMap"
            case .topSizes: return "Sizes"
            case .ageMap: return "Age"
            case .folderGrid: return "Grid"
            case .radial: return "Radial"
            case .icicle: return "Icicle"
            case .treelist: return "Treelist"
            case .extCloud: return "ExtCloud"
            }
        }

        var symbol: String {
            switch self {
            case .treemap: return "square.grid.3x3.fill"
            case .sunburst: return "sun.max.fill"
            case .flame: return "flame.fill"
            case .bubbles: return "circle.dashed"
            case .mindMap: return "brain"
            case .topSizes: return "list.number"
            case .ageMap: return "calendar"
            case .folderGrid: return "square.grid.2x2.fill"
            case .radial: return "circle.circle.fill"
            case .icicle: return "chart.bar.fill"
            case .treelist: return "list.bullet.indent"
            case .extCloud: return "cloud.fill"
            }
        }
    }

    enum ScanPhase { case idle, scanning, done, failed }

    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let actionTitle: String
        static func == (l: Banner, r: Banner) -> Bool { l.id == r.id }
    }

    // Services (injected by DiskDoomApp).
    var permissions = PermissionsService()
    // The shared instance, so the UNUserNotificationCenter delegate it installs
    // in init is never deallocated out from under the app.
    var notifications = NotificationService.shared
    var license = LicenseStore()
    let scanner = RealScanEngine()
    let dupFinder = DuplicateFinder()

    // nil once onboarding has been completed (persisted — the wizard used to
    // replay on every launch because this was only ever set in memory).
    @Published var onboardingStep: OnboardingStep?
    @Published var scanPhase: ScanPhase = .idle
    @Published var scanProgress: Double = 0
    @Published var scanPath: String = ""
    @Published var scanFiles: Int = 0
    @Published var scanElapsed: Double = 0
    @Published var scanTargetName = "Full Mac"
    @Published var limitedMode = false
    @Published var sidebarTab: SidebarTab = .explore
    @Published var exploreView: ExploreView = .treemap
    @Published var selectedNode: ScanNode? = nil
    @Published var selectedApp: AppEntry? = nil
    @Published var inspectorVisible = true
    @Published var searchText = ""
    @Published var banner: Banner? = nil

    @Published var showCleanup = false
    @Published var showDeleteConfirm = false
    @Published var uninstallApp: AppEntry? = nil
    @Published var quickLookNode: ScanNode? = nil
    @Published var showLicense = false

    @Published var cleanupItems: [CleanupItem] = []
    @Published var duplicateKeeps: [UUID: UUID] = [:]
    @Published var snapshots: [Snapshot] = []
    @Published var compareIDs: [UUID] = []
    @Published var trashFailures: [TrashFailure] = []
    @Published var freedBytes: Int64 = 0
    @Published var freedCount: Int = 0

    // Real scan data (nil until a scan or cached scan completes).
    @Published var scanRoot: ScanNode? = nil
    @Published var records: [ScannedRecord] = []
    @Published var skippedPaths: [String] = []
    @Published var lastScanDate: Date? = nil

    // Settings (persisted).
    @Published var includeHidden = true
    @Published var followSymlinks = false
    @Published var maxDepth = 0
    @Published var excludedPaths: [String] = []
    @Published var dupMinBytes: Int64 = 10_000_000
    @Published var snapshotRetention = 30
    @Published var autoSaveSnapshots = true
    @Published var notifyOnScan = true
    @Published var monitorThresholdBytes: Int64 = 100_000_000
    @Published var scheduleFrequency = "never" // never/daily/weekly/monthly
    @Published var accentName = "system"

    private var scanTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var scanRootURL: URL = URL(fileURLWithPath: "/")

    private static let onboardingCompletedKey = "onboardingCompleted"

    /// Replays the wizard only on a genuine first launch.
    static var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingCompletedKey)
    }

    /// Clears the completion flag — used by Settings → "Run onboarding again".
    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.onboardingCompletedKey)
        onboardingStep = .welcome
    }

    init() {
        loadSettings()
        onboardingStep = Self.hasCompletedOnboarding ? nil : .welcome
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
        if let raw = UserDefaults.standard.string(forKey: "sidebarTab"),
           let tab = SidebarTab(rawValue: raw) { sidebarTab = tab }
        if let raw = UserDefaults.standard.string(forKey: "exploreView"),
           let view = ExploreView(rawValue: raw) { exploreView = view }
        inspectorVisible = UserDefaults.standard.object(forKey: "inspectorVisible") as? Bool ?? true
        scanner.$progress.receive(on: DispatchQueue.main).assign(to: &$scanProgress)
        scanner.$currentPath.receive(on: DispatchQueue.main).assign(to: &$scanPath)
        scanner.$filesFound.receive(on: DispatchQueue.main).assign(to: &$scanFiles)
    }

    // MARK: Derived data (real when available, mock fallback)

    var effectiveRoot: ScanNode { scanRoot ?? ScanNode(name: "No scan", path: "/", sizeBytes: 0, category: .other, fileCount: 0) }
    var effectiveTopLevel: [ScanNode] { effectiveRoot.children }

    var cleanupTotal: Int64 { cleanupItems.reduce(0) { $0 + $1.bytes } }

    var ageBuckets: [AgeBucket] {
        guard !records.isEmpty else { return [] }
        let now = Date()
        let day: TimeInterval = 86_400
        var totals = Array(repeating: Int64(0), count: 9)
        var counts = Array(repeating: 0, count: 9)
        for record in records where !record.isDirectory {
            let age = now.timeIntervalSince(record.modified)
            let bucket: Int
            // RealScanEngine.fileMeta returns `.distantPast` when `lstat` fails, so
            // unreadable files must land in the "Never modified" bar (index 8).
            // Without this the 9th bar always rendered "0 bytes · 0 files" as if
            // it were a real measurement.
            if record.modified == .distantPast {
                bucket = 8
            } else {
                switch age {
                case ..<day: bucket = 0
                case ..<(7 * day): bucket = 1
                case ..<(30 * day): bucket = 2
                case ..<(90 * day): bucket = 3
                case ..<(180 * day): bucket = 4
                case ..<(365 * day): bucket = 5
                case ..<(730 * day): bucket = 6
                // Negative age = future-dated file (clock skew, restored backup).
                // Dropping it into "Now" inflates that bar with stale mtimes, so
                // anything outside the known ranges goes to "2+ years" instead.
                default: bucket = 7
                }
            }
            totals[bucket] += record.bytes
            counts[bucket] += 1
        }
        let labels = ["Now (< 1 day)", "1 day – 1 week", "1 week – 1 month", "1 – 3 months",
                      "3 – 6 months", "6 – 12 months", "1 – 2 years", "2+ years", "Never modified"]
        let colors: [Color] = [.green, .green, .yellow, .yellow, .orange, .orange, .red, .red, .gray]
        return (0..<9).map { i in AgeBucket(label: labels[i], bytes: totals[i], files: counts[i], color: colors[i]) }
    }

    // MARK: Real scan lifecycle

    func finishOnboarding() {
        onboardingStep = nil
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
        refreshLimitedMode()
    }

    /// Limited mode is *derived* from the real Full Disk Access state.
    /// Every onboarding skip button used to hardcode `limitedMode = true`,
    /// including the paths where the user then chose "Full Mac" — so the
    /// banner lied in both directions.
    func refreshLimitedMode() {
        limitedMode = !permissions.fdaGranted
    }

    func startScan(target: String? = nil) {
        if let target { scanTargetName = target }
        scanRootURL = urlForTarget(scanTargetName)
        startRealScan()
    }

    func startRealScan(root: URL? = nil, label: String? = nil) {
        if let root { scanRootURL = root }
        if let label { scanTargetName = label }
        scanTask?.cancel()
        scanPhase = .scanning
        scanProgress = 0
        scanFiles = 0
        skippedPaths = []
        let startedAt = Date()
        // Full-disk scans skip kernel/virtual mounts and other volumes by
        // default — they cost minutes and contain no cleanable user data.
        // (Volumes are scanned individually from their own targets.)
        var excluded = excludedPaths.map { ($0 as NSString).expandingTildeInPath }
        if scanRootURL.path == "/" {
            excluded += ["/dev", "/Volumes", "/.Spotlight-V100", "/.fseventsd", "/System/Volumes/Update"]
            // Limited mode actually has to *do* something. Previously the flag
            // was set by every onboarding skip path and displayed as a banner
            // but never consulted here, so a "Limited mode — Full Disk Access
            // not granted" notice sat above a full-disk scan.
            if limitedMode || !permissions.fdaGranted {
                excluded += [
                    "/System", "/Library", "/private/var", "/private/etc",
                    "/Applications", "/usr", "/bin", "/sbin", "/opt",
                ]
            }
        }
        let options = ScanOptions(
            includeHidden: includeHidden,
            followSymlinks: followSymlinks,
            maxDepth: maxDepth,
            excludedPaths: excluded)
        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await PerformanceMonitor.measure("RealScanEngine.scan", threshold: 30) {
                await scanner.scan(root: scanRootURL, label: scanTargetName, options: options)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                PerformanceMonitor.checkMemory(label: "AppState after scan", warningMB: 600)
                self.scanElapsed = Date().timeIntervalSince(startedAt)
                self.applyResult(result)
            }
        }
    }

    private func urlForTarget(_ target: String) -> URL {
        if target.hasPrefix("/Volumes/") || target.hasPrefix("/") {
            return URL(fileURLWithPath: target)
        }
        switch target {
        case "Home Folder": return FileManager.default.homeDirectoryForCurrentUser
        default: return URL(fileURLWithPath: "/")
        }
    }

    private func applyResult(_ result: ScanResult) {
        scanRoot = result.root
        records = result.records
        skippedPaths = result.skipped
        lastScanDate = Date()
        UserDefaults.standard.set(lastScanDate, forKey: "lastScanDate")
        if result.root.fileCount == 0 {
            // Total failure (e.g. unreadable external volume) — nothing to show.
            scanPhase = .failed
        } else {
            scanPhase = .done
            selectedNode = result.root.children.first
            if result.isPartial {
                banner = Banner(
                    message: "Partial scan · \(result.skipped.count) folders unreadable · \(result.root.fileCount.formatted()) files mapped",
                    actionTitle: "Details")
            } else {
                banner = Banner(
                    message: "Scan complete · \(result.root.fileCount.formatted()) files · \(result.root.sizeString) · \(String(format: "%.1f", result.elapsed))s",
                    actionTitle: "View Results")
            }
            dismissBannerAfterDelay()
            if notifyOnScan {
                notifications.postScanComplete(files: result.root.fileCount, bytes: result.root.sizeBytes, seconds: result.elapsed)
            }
            if autoSaveSnapshots {
                saveSnapshotFromCurrentScan(label: "Scan")
            }
            // Persist to the SQLite index in the background: failed writes
            // must never break the scan that just completed.
            let persistedRoot = result.root
            let persistedRecords = result.records
            let persistedElapsed = result.elapsed
            let persistedLabel = scanTargetName
            Task.detached {
                try? await ScanDatabase.shared.saveScan(
                    root: persistedRoot, records: persistedRecords,
                    label: persistedLabel, elapsed: persistedElapsed)
            }
        }
    }

    /// Launch hydration: instant tree from SQLite, records stream in after.
    /// Called by the launch coordinator; safe to call when nothing is cached.
    func restoreCachedScan() async {
        guard scanRoot == nil,
              let cached = try? await ScanDatabase.shared.latestScan(),
              let tree = cached.tree
        else { return }
        scanRoot = tree
        scanTargetName = cached.label
        lastScanDate = cached.date
        scanElapsed = cached.elapsed
        selectedNode = tree.children.first
        let scanID = cached.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            var all: [ScannedRecord] = []
            var offset = 0
            while true {
                let batch = (try? await ScanDatabase.shared.loadFiles(scanID: scanID, limit: 20_000, offset: offset)) ?? []
                if batch.isEmpty { break }
                all += batch
                offset += batch.count
                if Task.isCancelled { return }
            }
            self.records = all
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        // Keep previous results if any; otherwise idle.
        scanPhase = scanRoot == nil ? .idle : .done
    }

    func retryScan() {
        startRealScan()
    }

    /// On-demand expansion of a collapsed smart leaf: measures just that
    /// subtree and splices the children into the live tree + record index.
    func expandNode(path: String) {
        guard let root = scanRoot else { return }
        let options = ScanOptions(
            includeHidden: includeHidden,
            followSymlinks: followSymlinks,
            maxDepth: 0,
            excludedPaths: excludedPaths.map { ($0 as NSString).expandingTildeInPath })
        let result = scanner.expandSubtree(path: path, options: options)
        guard !result.children.isEmpty else { return }
        scanRoot = replaceNode(in: root, matching: path, with: result.children)
        let room = max(0, 1_000_000 - records.count)
        records += result.records.prefix(room)
        selectedNode = findNode(in: scanRoot, path: path)
    }

    private func replaceNode(in node: ScanNode, matching path: String, with children: [ScanNode]) -> ScanNode {
        if node.path == path {
            return ScanNode(
                id: node.id, name: node.name, path: node.path, sizeBytes: node.sizeBytes,
                category: node.category, fileCount: node.fileCount, children: children,
                modified: node.modified, physicalBytes: node.physicalBytes,
                isCollapsed: false, collapseReason: nil)
        }
        return ScanNode(
            id: node.id, name: node.name, path: node.path, sizeBytes: node.sizeBytes,
            category: node.category, fileCount: node.fileCount,
            children: node.children.map { replaceNode(in: $0, matching: path, with: children) },
            modified: node.modified, physicalBytes: node.physicalBytes,
            isCollapsed: node.isCollapsed, collapseReason: node.collapseReason)
    }

    private func findNode(in node: ScanNode?, path: String) -> ScanNode? {
        guard let node else { return nil }
        if node.path == path { return node }
        for child in node.children {
            if let found = findNode(in: child, path: path) { return found }
        }
        return nil
    }

    // MARK: Cleanup queue (real Trash)

    /// Reasons a path can never be staged for deletion. Checked here AND
    /// again inside `TrashService.trash` so no code path can bypass them.
    static func isProtectedFromDeletion(_ path: String) -> String? {
        let p = (path as NSString).expandingTildeInPath
        guard p.hasPrefix("/") else { return "not an absolute path" }
        // The synthetic "Other (N items)" tail node carries no path of its
        // own; staging it used to trash its entire parent folder.
        guard !p.isEmpty else { return "not a real filesystem item" }
        if p == "/" || p == "/System" || p == "/Library" || p == "/Applications"
            || p == "/Users" || p == "/private" || p == "/opt" || p == "/usr"
            || p == "/bin" || p == "/sbin" || p == "/dev" || p == "/cores"
            || p == "/Volumes" || p == "/Network" || p == "/home" || p == "/var" {
            return "system directory"
        }
        for blocked in [
            "/System/", "/Library/Extensions/", "/Library/LaunchDaemons/",
            "/Library/LaunchAgents/", "/Library/Keychains/", "/private/var/db/",
            "/private/var/folders/", "/private/etc/", "/usr/", "/bin/", "/sbin/",
            "/dev/", "/cores/", "/Volumes/.Spotlight-V100", "/.VolumeIcon.icns",
        ] where p.hasPrefix(blocked) {
            return "protected system path"
        }
        // Never let the app delete itself.
        let ownBundle = Bundle.main.bundlePath
        if !ownBundle.isEmpty, p == ownBundle || p.hasPrefix(ownBundle + "/") {
            return "this is DiskDoom itself"
        }
        return nil
    }

    /// Stage a path for cleanup. Returns false (and stages nothing) when the
    /// path is unsafe, so a caller can surface the reason.
    @discardableResult
    func stage(source: String, path: String, bytes: Int64 = -1) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return false }
        if let reason = Self.isProtectedFromDeletion(expanded) {
            banner = Banner(message: "Refused to queue \(expanded) — \(reason).", actionTitle: "OK")
            return false
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else { return false }

        // De-duplicate on the expanded path: staging "~/Library/Containers/x"
        // and "/Users/me/Library/Containers/x" used to queue it twice.
        if !cleanupItems.contains(where: { ($0.path as NSString).expandingTildeInPath == expanded }) {
            // Reject ancestor/descendant overlaps — trashing both a folder
            // and something inside it double-counts and the second move fails.
            for existing in cleanupItems {
                let e = (existing.path as NSString).expandingTildeInPath
                if expanded.hasPrefix(e + "/") || e.hasPrefix(expanded + "/") {
                    banner = Banner(message: "Already queued: \(e) overlaps \(expanded).", actionTitle: "OK")
                    return false
                }
            }
            let size = bytes >= 0 ? bytes : Self.measureStagedSize(at: expanded, isDirectory: isDir.boolValue)
            cleanupItems.append(CleanupItem(source: source, path: expanded, bytes: size))
        }
        return true
    }

    /// Size to display for a staged item. `totalFileSizeKey` returns the
    /// *inode* size for directories (~4 KB), which made every staged folder
    /// report "4 KB" and "0 B freed"; measure directories properly instead.
    static func measureStagedSize(at path: String, isDirectory: Bool) -> Int64 {
        if isDirectory {
            var total: Int64 = 0
            var stack: [String] = [path]
            var seen = 0
            while let dir = stack.popLast() {
                seen += 1
                if seen > 20_000 { break } // bounded: display value only
                guard let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                for kid in kids {
                    let child = dir + "/" + kid
                    var st = stat()
                    guard lstat(child, &st) == 0 else { continue }
                    if (st.st_mode & S_IFMT) == S_IFDIR {
                        stack.append(child)
                    } else {
                        let (s, o) = total.addingReportingOverflow(Int64(st.st_size))
                        total = o ? Int64.max : s
                    }
                }
            }
            return total
        }
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        return Int64(st.st_size)
    }

    @discardableResult
    func executeCleanup() -> TrashResult {
        guard license.canClean else {
            banner = Banner(message: "Read-only mode — trial expired. Activate a license to clean.", actionTitle: "Activate")
            showDeleteConfirm = false
            return TrashResult(trashedBytes: 0, trashedCount: 0, failures: [])
        }
        let result = TrashService.trash(paths: cleanupItems.map { ($0.path, $0.bytes) })
        trashFailures = result.failures.map {
            TrashFailure(path: $0.path, bytes: $0.bytes, reason: $0.reason)
        }
        let failedPaths = Set(result.failures.map(\.path))
        cleanupItems.removeAll { failedPaths.contains($0.path) }
        freedBytes += result.trashedBytes
        freedCount += result.trashedCount
        showDeleteConfirm = false
        if result.failures.isEmpty {
            showCleanup = false
            banner = Banner(message: "Moved \(result.trashedCount) items to Trash · \(ByteFormatting.format(result.trashedBytes)) freed", actionTitle: "Show Trash")
            dismissBannerAfterDelay()
            notifications.postCleanupComplete(items: result.trashedCount, freed: result.trashedBytes)
        }
        // Else: queue sheet stays open showing the §31C failure report + retry.
        return result
    }

    func showTrashInFinder() {
        let trash = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        NSWorkspace.shared.open(trash)
        banner = nil
    }

    func dismissBannerAfterDelay() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.banner = nil
        }
    }

    // MARK: Snapshots (real persistence)

    func saveSnapshotFromCurrentScan(label: String) {
        guard let root = scanRoot else { return }
        var top: [String: Int64] = [:]
        for child in root.children { top[child.name] = child.sizeBytes }
        ScanStore.saveSnapshot(date: Date(), label: label, target: scanTargetName, totalBytes: root.sizeBytes, files: root.fileCount, topDirs: top)
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
    }

    func deleteSnapshot(_ snapshot: Snapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        ScanStore.removeSnapshot(date: snapshot.date)
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
    }

    // MARK: Settings persistence

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(includeHidden, forKey: "setIncludeHidden")
        defaults.set(followSymlinks, forKey: "setFollowSymlinks")
        defaults.set(maxDepth, forKey: "setMaxDepth")
        defaults.set(excludedPaths, forKey: "setExcludedPaths")
        defaults.set(dupMinBytes, forKey: "setDupMinBytes")
        defaults.set(snapshotRetention, forKey: "setSnapshotRetention")
        defaults.set(autoSaveSnapshots, forKey: "setAutoSaveSnapshots")
        defaults.set(notifyOnScan, forKey: "setNotifyOnScan")
        defaults.set(monitorThresholdBytes, forKey: "setMonitorThreshold")
        defaults.set(scheduleFrequency, forKey: "setScheduleFrequency")
        defaults.set(accentName, forKey: "setAccentName")
        defaults.set(sidebarTab.rawValue, forKey: "sidebarTab")
        defaults.set(exploreView.rawValue, forKey: "exploreView")
        defaults.set(inspectorVisible, forKey: "inspectorVisible")
        snapshots = ScanStore.loadSnapshots(retention: snapshotRetention)
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "setIncludeHidden") != nil {
            includeHidden = defaults.bool(forKey: "setIncludeHidden")
            followSymlinks = defaults.bool(forKey: "setFollowSymlinks")
            maxDepth = defaults.integer(forKey: "setMaxDepth")
            excludedPaths = defaults.stringArray(forKey: "setExcludedPaths") ?? []
            dupMinBytes = Int64(defaults.integer(forKey: "setDupMinBytes") == 0 ? 10_000_000 : defaults.integer(forKey: "setDupMinBytes"))
            snapshotRetention = defaults.integer(forKey: "setSnapshotRetention") == 0 ? 30 : defaults.integer(forKey: "setSnapshotRetention")
            autoSaveSnapshots = defaults.object(forKey: "setAutoSaveSnapshots") as? Bool ?? true
            notifyOnScan = defaults.bool(forKey: "setNotifyOnScan")
            if defaults.object(forKey: "setMonitorThreshold") != nil {
                monitorThresholdBytes = Int64(defaults.integer(forKey: "setMonitorThreshold"))
            }
            scheduleFrequency = defaults.string(forKey: "setScheduleFrequency") ?? "never"
            accentName = defaults.string(forKey: "setAccentName") ?? "system"
        }
    }

    // MARK: Scheduled scans (config persisted; fires on launch when due)

    func startupCheck() {
        license.refresh()
        Task { [weak self] in
            guard let self else { return }
            await license.validateOnLaunch()
            if let update = license.updateAvailable {
                banner = Banner(message: "Update \(update) is available (Check for Updates in Settings).", actionTitle: "Dismiss")
            } else if let message = license.lastServerMessage, !license.isLicensed {
                banner = Banner(message: message, actionTitle: "Activate")
            }
        }
        guard scheduleFrequency != "never" else { return }
        let last = UserDefaults.standard.object(forKey: "lastAutoScan") as? Date ?? .distantPast
        let interval: TimeInterval
        switch scheduleFrequency {
        case "daily": interval = 86_400
        case "weekly": interval = 7 * 86_400
        default: interval = 30 * 86_400
        }
        if Date().timeIntervalSince(last) >= interval {
            UserDefaults.standard.set(Date(), forKey: "lastAutoScan")
            startRealScan()
        }
    }
}
