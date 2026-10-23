import SwiftUI
import Combine
import AppKit

// MARK: - App state: real scan lifecycle, trash, snapshots, notifications, trial

@MainActor
final class AppState: ObservableObject {
    enum OnboardingStep { case welcome, fullDiskAccess, scanTarget }
    enum SidebarTab: String, CaseIterable {
        case explore, duplicates, similar, applications, monitor, snapshots
        case dupMonitor
        case litterScore, forecast, simulator, devCaches, health, budgets, liveFeed
        case lifecycle, provenance, compression, containers, privacy, photos
        case smartClean, storage, folders
        case progress
        case developer, pro3D, videoEditor
        var title: String {
            switch self {
            case .explore: return "Explore"
            case .duplicates: return "Duplicates"
            case .similar: return "Similar Files"
            case .dupMonitor: return "Duplicate Monitor"
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
            case .progress: return "Progress"
            case .developer: return "Dev Projects"
            case .pro3D: return "3D & Creative"
            case .videoEditor: return "Video Caches"
            }
        }

        var symbol: String {
            switch self {
            case .explore: return "magnifyingglass"
            case .duplicates: return "doc.on.doc"
            case .similar: return "photo.on.rectangle.angled"
            case .dupMonitor: return "binoculars.fill"
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
            case .progress: return "trophy.fill"
            case .developer: return "hammer.fill"
            case .pro3D: return "cube.fill"
            case .videoEditor: return "film.fill"
            }
        }

        static var primary: [SidebarTab] {
            [.explore, .duplicates, .similar, .applications, .monitor, .snapshots, .dupMonitor, .progress]
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

        /// One hue per visualization so the Explore tab reads as a spectrum
        /// rather than a single blue control strip. The label and SF Symbol
        /// remain the primary identifiers; the hue is reinforcement only.
        var tint: Color {
            switch self {
            case .treemap: return DesignTokens.Spectrum.color(at: 0)
            case .sunburst: return DesignTokens.Spectrum.color(at: 3)
            case .flame: return DesignTokens.Spectrum.color(at: 11)
            case .bubbles: return DesignTokens.Spectrum.color(at: 7)
            case .mindMap: return DesignTokens.Spectrum.color(at: 1)
            case .topSizes: return DesignTokens.Spectrum.color(at: 4)
            case .ageMap: return DesignTokens.Spectrum.color(at: 9)
            case .folderGrid: return DesignTokens.Spectrum.color(at: 8)
            case .radial: return DesignTokens.Spectrum.color(at: 10)
            case .icicle: return DesignTokens.Spectrum.color(at: 5)
            case .treelist: return DesignTokens.Spectrum.color(at: 6)
            case .extCloud: return DesignTokens.Spectrum.color(at: 2)
            }
        }

        var purpose: String {
            switch self {
            case .treemap: return "Compare folder sizes as proportional tiles."
            case .sunburst: return "Explore folders by depth in a circular map."
            case .flame: return "Follow the largest branches of the scan."
            case .bubbles: return "Compare folders as size-scaled circles."
            case .mindMap: return "Trace parent and child folders side by side."
            case .topSizes: return "Find the largest mapped folders."
            case .ageMap: return "Compare indexed files by modification age."
            case .folderGrid: return "Browse folders as sortable-size cards."
            case .radial: return "Inspect two levels of folders in depth rings."
            case .icicle: return "Compare folder sizes across levels."
            case .treelist: return "Expand the folder hierarchy as a list."
            case .extCloud: return "Find file types consuming the most space."
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
    let similarFinder = SimilarPhotoFinder()
    let photoDuplicates = PhotoDuplicatesEngine()
    let duplicateMonitor = DuplicateMonitor()
    let ignoreRules = IgnoreRules()
    let priorities = ScanPriorityStore()
    let gamification = GamificationEngine()

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
    @Published private(set) var indexedScanLabel: String?
    /// One-shot navigation target sent by global search to the Folders browser.
    @Published var folderSearchDestination: String?
    /// Tracks actual index changes, including subtree expansion at the record cap.
    @Published private(set) var searchRevision = 0
    @Published var banner: Banner? = nil

    @Published var showCleanup = false
    @Published var showDeleteConfirm = false
    @Published var uninstallApp: AppEntry? = nil
    @Published var quickLookNode: ScanNode? = nil
    @Published var showLicense = false

    @Published var cleanupItems: [CleanupItem] = [] {
        didSet {
            let pendingIDs = Set(cleanupItems.filter { $0.sizeState == .measuring }.map(\.id))
            for id in Array(cleanupMeasurementTasks.keys) where !pendingIDs.contains(id) {
                cleanupMeasurementTasks.removeValue(forKey: id)?.cancel()
            }
        }
    }
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
    @Published var removalMethod = RemovalMethod.trash.rawValue
    @Published var removalDestination = ""
    @Published var removalOverwrite = false
    @Published var snapshotRetention = 30
    @Published var autoSaveSnapshots = true
    @Published var notifyOnScan = true
    @Published var monitorThresholdBytes: Int64 = 100_000_000
    @Published var scheduleFrequency = "never" // never/daily/weekly/monthly
    @Published var accentName = "system"

    private var scanTask: Task<Void, Never>?
    private var cachedRecordsTask: Task<Void, Never>?
    private var expansionTask: Task<Void, Never>?
    private var cleanupMeasurementTasks: [UUID: Task<Void, Never>] = [:]
    private var scanGeneration = UUID()
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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestMainWindow") { onboardingStep = nil }
        if let index = arguments.firstIndex(of: "-uiTestTab"),
           index + 1 < arguments.count,
           let tab = SidebarTab(rawValue: arguments[index + 1]) {
            sidebarTab = tab
        }
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

    var cleanupTotal: Int64 { CleanupItem.knownTotal(cleanupItems) }
    var cleanupSizeSummary: String { CleanupItem.sizeSummary(cleanupItems) }
    var cleanupIsMeasuring: Bool { cleanupItems.contains { $0.sizeState == .measuring } }

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
            // unreadable dates must land in the "Unknown date" bar (index 8).
            // Without this the 9th bar always rendered "0 bytes · 0 files" as if
            // it were a real measurement.
            if record.modified == .distantPast || age < 0 {
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
                // Remaining known dates are at least two years old.
                default: bucket = 7
                }
            }
            totals[bucket] += record.bytes
            counts[bucket] += 1
        }
        let labels = ["Now (< 1 day)", "1 day – 1 week", "1 week – 1 month", "1 – 3 months",
                       "3 – 6 months", "6 – 12 months", "1 – 2 years", "2+ years", "Unknown date"]
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
        cachedRecordsTask?.cancel()
        cachedRecordsTask = nil
        expansionTask?.cancel()
        expansionTask = nil
        scanGeneration = UUID()
        scanPhase = .scanning
        scanProgress = 0
        scanFiles = 0
        skippedPaths = []
        let startedAt = Date()
        // Full-disk scans skip kernel/virtual mounts and other volumes by
        // default — they cost minutes and contain no cleanable user data.
        // (Volumes are scanned individually from their own targets.)
        var excluded = (excludedPaths + ignoreRules.ignoredPaths)
            .map { ($0 as NSString).expandingTildeInPath }
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
        let scanner = self.scanner
        let scanURL = scanRootURL
        let scanLabel = scanTargetName
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await PerformanceMonitor.measure("RealScanEngine.scan", threshold: 30) {
                await scanner.scan(root: scanURL, label: scanLabel, options: options)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.scanGeneration == generation else { return }
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
        searchRevision &+= 1
        indexedScanLabel = scanTargetName
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
            gamification.record(GameEvent(kind: .scan, filesScanned: result.root.fileCount))
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
        let generation = scanGeneration
        guard scanRoot == nil, scanPhase != .scanning,
              let cached = try? await ScanDatabase.shared.latestScan(),
              scanGeneration == generation, scanRoot == nil, scanPhase != .scanning,
              let tree = cached.tree
        else { return }
        scanRoot = tree
        searchRevision &+= 1
        indexedScanLabel = cached.label
        scanTargetName = cached.label
        lastScanDate = cached.date
        scanElapsed = cached.elapsed
        selectedNode = tree.children.first
        let scanID = cached.id
        cachedRecordsTask?.cancel()
        cachedRecordsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var all: [ScannedRecord] = []
            var offset = 0
            while true {
                let batch = (try? await ScanDatabase.shared.loadFiles(scanID: scanID, limit: 20_000, offset: offset)) ?? []
                guard !Task.isCancelled, self.scanGeneration == generation else { return }
                if batch.isEmpty { break }
                all += batch
                offset += batch.count
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled, self.scanGeneration == generation else { return }
            self.records = all
            self.searchRevision &+= 1
        }
    }

    func cancelScan() {
        scanGeneration = UUID()
        expansionTask?.cancel()
        expansionTask = nil
        cachedRecordsTask?.cancel()
        cachedRecordsTask = nil
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
        guard path.hasPrefix("/"), scanPhase != .scanning,
              let node = findNode(in: scanRoot, path: path), node.isActionable, node.isCollapsed else { return }
        expansionTask?.cancel()
        let options = ScanOptions(
            includeHidden: includeHidden,
            followSymlinks: followSymlinks,
            maxDepth: 0,
            excludedPaths: excludedPaths.map { ($0 as NSString).expandingTildeInPath })
        let generation = scanGeneration
        expansionTask = Task { [weak self] in
            // Separate scanner: never share mutable scanner state with a
            // full scan. Cancellation is forwarded to the detached walk.
            let worker = Task.detached(priority: .userInitiated) {
                RealScanEngine().expandSubtree(path: path, options: options)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, self.scanGeneration == generation,
                  let root = self.scanRoot,
                  self.findNode(in: root, path: path)?.isCollapsed == true,
                  !result.children.isEmpty else { return }
            self.scanRoot = self.replaceNode(in: root, matching: path, with: result.children)
            let room = max(0, 1_000_000 - self.records.count)
            self.records += result.records.prefix(room)
            self.searchRevision &+= 1
            if self.selectedNode?.path == path {
                self.selectedNode = self.findNode(in: self.scanRoot, path: path)
            }
        }
    }

    private func replaceNode(in node: ScanNode, matching path: String, with children: [ScanNode]) -> ScanNode {
        if node.path == path {
            return ScanNode(
                id: node.id, name: node.name, path: node.path, sizeBytes: node.sizeBytes,
                category: node.category, fileCount: node.fileCount, children: children,
                modified: node.modified, physicalBytes: node.physicalBytes,
                isCollapsed: false, collapseReason: nil,
                isSyntheticAggregate: node.isSyntheticAggregate,
                isPartial: node.isPartial || children.contains(where: \.isPartial))
        }
        return ScanNode(
            id: node.id, name: node.name, path: node.path, sizeBytes: node.sizeBytes,
            category: node.category, fileCount: node.fileCount,
            children: node.children.map { replaceNode(in: $0, matching: path, with: children) },
            modified: node.modified, physicalBytes: node.physicalBytes,
            isCollapsed: node.isCollapsed, collapseReason: node.collapseReason,
            isSyntheticAggregate: node.isSyntheticAggregate, isPartial: node.isPartial)
    }

    /// Resolve navigation from the current scan tree, not a chart's captured
    /// node (which becomes stale when a collapsed folder is expanded).
    func currentScanNode(path: String) -> ScanNode? {
        guard var node = scanRoot else { return nil }
        while node.path != path {
            guard let child = node.children.first(where: {
                !$0.path.isEmpty && (path == $0.path || path.hasPrefix($0.path + "/"))
            }) else { return nil }
            node = child
        }
        return node
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
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return "not an absolute path" }
        // Use the same lexical/resolved protections as the final Trash
        // backstop rather than maintain a second, divergent deny-list.
        return TrashService.deletionRefusal(for: expanded)
    }

    /// Stage a path for cleanup. Returns false (and stages nothing) when the
    /// path is unsafe, so a caller can surface the reason.
    @discardableResult
    func stage(source: String, path: String, bytes: Int64 = -1) -> Bool {
        let raw = (path as NSString).expandingTildeInPath
        guard raw.hasPrefix("/") else { return false }
        let expanded = (raw as NSString).standardizingPath
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
            var st = stat()
            // lstat prevents following a selected symlink into its target.
            guard lstat(expanded, &st) == 0 else { return false }
            let needsMeasurement = bytes < 0 && (st.st_mode & S_IFMT) == S_IFDIR
            let size = bytes >= 0 ? bytes : (needsMeasurement ? 0 : max(0, Int64(st.st_size)))
            let item = CleanupItem(source: source, path: expanded, bytes: size,
                                   sizeState: needsMeasurement ? .measuring : (bytes >= 0 ? .provided : .measured))
            cleanupItems.append(item)
            if needsMeasurement { measureQueuedDirectory(item) }
        }
        return true
    }

    /// Await only the original selected queue identities. A removed/restaged
    /// path is not renewed consent to execute the replacement item.
    func awaitCleanupMeasurements(for selection: [String: UUID]) async -> Set<String> {
        let tasks = selection.values.compactMap { cleanupMeasurementTasks[$0] }
        for task in tasks {
            await task.value
            if Task.isCancelled { return [] }
        }
        guard !Task.isCancelled else { return [] }
        return Set(selection.compactMap { path, id in
            cleanupItems.contains { $0.path == path && $0.id == id && $0.sizeState != .measuring } ? path : nil
        })
    }

    private func measureQueuedDirectory(_ item: CleanupItem) {
        cleanupMeasurementTasks[item.id] = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .utility) {
                Self.measureStagedDirectory(at: item.path)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled,
                  let index = self.cleanupItems.firstIndex(where: {
                      $0.id == item.id && $0.path == item.path && $0.sizeState == .measuring
                  }) else { return }
            self.cleanupMeasurementTasks.removeValue(forKey: item.id)
            self.cleanupItems[index].bytes = result.bytes
            self.cleanupItems[index].sizeState = result.complete ? .measured : (result.bytes > 0 ? .lowerBound : .unknown)
        }
    }

    /// Synchronous compatibility helper for single-file stat/tests. Queue
    /// directory walks use the detached method above, never this on the UI.
    nonisolated static func measureStagedSize(at path: String, isDirectory: Bool) -> Int64 {
        if isDirectory { return measureStagedDirectory(at: path).bytes }
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        return max(0, Int64(st.st_size))
    }

    /// Logical contents size; a bounded streaming traversal. A partial zero
    /// means unknown, not an assertion that the directory is empty.
    nonisolated static func measureStagedDirectory(at path: String, entryLimit: Int = 20_000,
                                                   timeLimit: TimeInterval = 3) -> (bytes: Int64, complete: Bool) {
        guard !Task.isCancelled else { return (0, false) }
        var total: Int64 = 0
        var complete = true
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeLimit)
        var root = stat()
        guard lstat(path, &root) == 0, (root.st_mode & S_IFMT) == S_IFDIR else { return (0, false) }
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, _ in complete = false; return true }) else { return (0, false) }
        var seen = 0
        while true {
            if Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline { return (total, false) }
            guard let child = enumerator.nextObject() as? URL else { break }
            seen += 1
            if seen > max(0, entryLimit) { return (total, false) }
            var st = stat()
            guard lstat(child.path, &st) == 0 else { complete = false; continue }
            if (st.st_mode & S_IFMT) == S_IFLNK { enumerator.skipDescendants() }
            guard (st.st_mode & S_IFMT) != S_IFDIR else { continue }
            let (sum, overflow) = total.addingReportingOverflow(max(0, Int64(st.st_size)))
            if overflow { complete = false }
            total = overflow ? Int64.max : sum
        }
        return (total, complete)
    }

    @discardableResult
    func executeCleanup(onlyPaths: Set<String>? = nil) -> TrashResult {
        guard license.canClean else {
            banner = Banner(message: "Read-only mode — trial expired. Activate a license to clean.", actionTitle: "Activate")
            showDeleteConfirm = false
            return TrashResult(trashedBytes: 0, trashedCount: 0, failures: [])
        }
        let selectedItems = cleanupItems.filter { onlyPaths?.contains($0.path) ?? true }
        guard !selectedItems.isEmpty else {
            return TrashResult(trashedBytes: 0, trashedCount: 0, failures: [])
        }
        guard !selectedItems.contains(where: { $0.sizeState == .measuring }) else {
            banner = Banner(message: "Selected folders are still being measured. Wait before moving them to Trash.", actionTitle: "OK")
            showDeleteConfirm = false
            return TrashResult(trashedBytes: 0, trashedCount: 0, failures: selectedItems.map {
                TrashFailure(path: $0.path, bytes: $0.bytes, reason: "Cleanup deferred while selected folders are being measured")
            })
        }
        let selectedPaths = Set(selectedItems.map(\.path))
        let result = TrashService.trash(paths: selectedItems.map { ($0.path, $0.hasKnownSize ? max(0, $0.bytes) : 0) })
        trashFailures = result.failures.map {
            TrashFailure(path: $0.path, bytes: $0.bytes, reason: $0.reason)
        }
        let failedPaths = Set(result.failures.map(\.path))
        cleanupItems.removeAll { selectedPaths.contains($0.path) && !failedPaths.contains($0.path) }
        let (movedBytes, overflow) = freedBytes.addingReportingOverflow(result.trashedBytes)
        freedBytes = overflow ? Int64.max : movedBytes
        freedCount += result.trashedCount
        // Attribute XP to the feature that staged each item, so duplicate and
        // similar-photo achievements advance even when cleanup runs through
        // the shared queue instead of a direct removal sheet.
        let succeeded = selectedItems.filter { !failedPaths.contains($0.path) }
        for (source, items) in Dictionary(grouping: succeeded, by: \.source) {
            let kind = GamificationEngine.sourceEventKind(forCleanupSource: source)
            let bytes = items.reduce(Int64(0)) { $0 + max(0, $1.bytes) }
            if !items.isEmpty {
                gamification.record(GameEvent(kind: kind, bytes: bytes, items: items.count))
            }
        }
        showDeleteConfirm = false
        if result.failures.isEmpty {
            showCleanup = !cleanupItems.isEmpty
            banner = Banner(message: "Moved \(result.trashedCount) items to Trash · \(CleanupItem.sizeSummary(selectedItems)). Storage is reclaimed only after emptying Trash.", actionTitle: "Show Trash")
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
        let bannerID = banner?.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, self?.banner?.id == bannerID else { return }
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
        defaults.set(removalMethod, forKey: "setRemovalMethod")
        defaults.set(removalDestination, forKey: "setRemovalDestination")
        defaults.set(removalOverwrite, forKey: "setRemovalOverwrite")
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
            removalMethod = defaults.string(forKey: "setRemovalMethod") ?? RemovalMethod.trash.rawValue
            removalDestination = defaults.string(forKey: "setRemovalDestination") ?? ""
            removalOverwrite = defaults.object(forKey: "setRemovalOverwrite") as? Bool ?? false
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
