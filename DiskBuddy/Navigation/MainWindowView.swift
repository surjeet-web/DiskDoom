import SwiftUI
import Combine

// MARK: - Main window: sidebar (§36) + toolbar (§35) + inspector (§13/§14) + banners (§34) + drop zone (§33)

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var topology: DiskTopologyService
    @EnvironmentObject var coordinator: LaunchCoordinator
    @EnvironmentObject var inventory: AppInventoryService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTargeted = false
    @State private var observedScanRootID: UUID?
    @State private var searchQuery = ""
    @State private var searchResult = GlobalSearchResult.empty
    @State private var activeSearch: SearchKey?
    @State private var completedSearch: SearchKey?
    @State private var appSearchRevision = 0
    @State private var requestedSearchInventory = false
    @FocusState private var searchFocused: Bool

    private struct SearchKey: Hashable {
        let query: String
        let scanRevision: Int
        let appsRevision: Int
    }

    private var searchKey: SearchKey {
        SearchKey(query: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                  scanRevision: state.searchRevision, appsRevision: appSearchRevision)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: DesignTokens.Layout.sidebarWidth)
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    if let banner = state.banner {
                        NotificationBannerView(banner: banner)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    // §31A: limited-mode notice when FDA was skipped.
                    if (state.limitedMode || !state.permissions.fdaGranted) && state.scanPhase != .scanning {
                        HStack {
                            Image(systemName: "lock.fill").foregroundStyle(.orange)
                            Text("Limited mode — Full Disk Access not granted.")
                                .font(.caption)
                            Spacer()
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        .padding(.horizontal, DesignTokens.Space.m)
                        .padding(.vertical, DesignTokens.Space.xs)
                        .background(.orange.opacity(0.08))
                    }
                    ZStack {
                        detailContent
                            .animation(reduceMotion ? nil : DesignTokens.Motion.navigation, value: state.sidebarTab)
                        // §33 drag-and-drop overlay.
                        if dropTargeted {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.l)
                                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                                .background(.ultraThickMaterial)
                                .overlay(
                                    VStack(spacing: DesignTokens.Space.m) {
                                        Image(systemName: "folder.badge.plus")
                                            .font(.system(size: 48))
                                            .foregroundStyle(Color.accentColor)
                                        Text("Drop folder to scan")
                                            .font(.title3.weight(.semibold))
                                    }
                                )
                                .padding(DesignTokens.Space.xl)
                        }
                    }
                    statusBar
                }
                .frame(minWidth: 500)
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    // Real folder drop: resolve the first dropped directory and scan it.
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        var isDir: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
                        DispatchQueue.main.async {
                            state.startRealScan(root: url, label: url.lastPathComponent)
                        }
                    }
                    return true
                }
                if state.inspectorVisible {
                    InspectorView()
                        .frame(minWidth: 240, idealWidth: DesignTokens.Layout.inspectorWidth, maxWidth: 360)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : DesignTokens.Motion.navigation, value: state.inspectorVisible)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(state.scanPhase == .scanning ? "Cancel" : "Scan") {
                    state.scanPhase == .scanning ? state.cancelScan() : state.startScan()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                TextField("Search everywhere", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .focused($searchFocused)
                    .onSubmit {
                        if activeSearch == searchKey, let first = searchResult.hits.first {
                            openSearchResult(first)
                        }
                    }
                    .help("Search sections, visualizations, installed apps, and indexed files (⌘F)")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Find", systemImage: "magnifyingglass") { searchFocused = true }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    withAnimation(reduceMotion ? nil : DesignTokens.Motion.navigation) {
                        state.inspectorVisible.toggle()
                    }
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    state.showCleanup = true
                } label: {
                    Label(
                        state.cleanupItems.isEmpty ? "Cleanup" : "Cleanup (\(state.cleanupItems.count))",
                        systemImage: "trash"
                    )
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    state.saveSnapshotFromCurrentScan(label: "Manual")
                    state.sidebarTab = .snapshots
                } label: {
                    Label("Snapshot", systemImage: "camera")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.scanRoot == nil)
            }
        }
        .sheet(isPresented: $state.showCleanup) {
            CleanupQueueSheet().environmentObject(state)
        }
        .sheet(item: $state.uninstallApp) { app in
            UninstallSheet(app: app).environmentObject(state).environmentObject(inventory)
        }
        .sheet(item: $state.quickLookNode) { node in
            QuickLookSheet(node: node).environmentObject(state)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.base), value: state.banner)
        .onAppear {
            state.startupCheck()
            Task {
                await topology.loadCapacity()
                await topology.loadExternals()
            }
        }
        .onReceive(state.$scanRoot) { root in
            if observedScanRootID != root?.id {
                observedScanRootID = root?.id
                state.selectedNode = nil
            }
        }
        .onReceive(inventory.$apps.dropFirst()) { _ in appSearchRevision &+= 1 }
        .onReceive(state.$sidebarTab.dropFirst()) { _ in
            state.searchText = ""
            searchQuery = ""
        }
        .onReceive(state.$exploreView.dropFirst()) { _ in
            state.searchText = ""
            searchQuery = ""
        }
        .task(id: searchKey) {
            let key = searchKey
            guard !key.query.isEmpty else {
                searchResult = .empty
                activeSearch = key
                completedSearch = key
                return
            }
            if !requestedSearchInventory && inventory.apps.isEmpty && !inventory.isScanning {
                requestedSearchInventory = true
                inventory.scan()
            }
            let apps = inventory.apps.map {
                SearchableApp(name: $0.name, bundleID: $0.bundleID,
                              path: $0.bundlePath.isEmpty ? $0.bundleID : $0.bundlePath,
                              bytes: $0.totalBytes)
            }
            let sections = AppState.SidebarTab.allCases.map { (id: $0.rawValue, title: $0.title) }
            let views = AppState.ExploreView.allCases.map { (id: $0.rawValue, title: $0.title) }
            let quick = GlobalSearch.find(query: key.query, records: [], root: nil,
                                          apps: apps, sections: sections, visualizations: views)
            guard !Task.isCancelled, searchKey == key else { return }
            activeSearch = key
            searchResult = quick
            if key.query.count < 2 {
                completedSearch = key
                return
            }
            // Sections and apps are already shown. Delay the full index pass
            // briefly so rapid typing doesn't start multiple large searches.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let records = state.records
            let root = state.scanRoot
            let worker = Task.detached(priority: .userInitiated) {
                GlobalSearch.find(query: key.query, records: records, root: root,
                                  apps: apps, sections: sections, visualizations: views)
            }
            let found = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, searchKey == key else { return }
            searchResult = found
            completedSearch = key
        }
    }

    // MARK: Sidebar (§36)

    private var sidebar: some View {
        List(selection: $state.sidebarTab) {
            Section {
                DiskDoomLogo(style: .sidebar, size: 28)
                    .padding(.vertical, DesignTokens.Space.xs)
            }
            Section("Navigate") {
                ForEach(AppState.SidebarTab.primary, id: \.self) { tab in
                    let shortcut = ["explore": 1, "duplicates": 2, "applications": 3, "monitor": 4, "snapshots": 5][tab.rawValue] ?? 0
                    Label {
                        HStack {
                            Text(tab.title)
                            Spacer()
                            Text("⌘\(shortcut)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: tab.symbol)
                    }
                    .tag(tab)
                }
            }
            Section("Insights") {
                ForEach(AppState.SidebarTab.insights, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .tag(tab)
                }
            }
            Section("Professional") {
                ForEach(AppState.SidebarTab.professional, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .tag(tab)
                }
            }
            Section("Favorites") {
                // These three were bare `Label`s with no `.tag(...)`, so they rendered
                // exactly like the real navigation rows above but selected nothing and
                // navigated nowhere — dead UI that read as broken. Now they are real
                // buttons that route to the Folders tab.
                favoriteShortcut("/Applications", symbol: "app.badge")
                favoriteShortcut("~/Downloads", symbol: "tray.and.arrow.down")
                favoriteShortcut("~/Library", symbol: "folder")
            }
            Section("Volumes") {
                Text("\(topology.dataVolumeName) — \(topology.currentCapacity.availableValue.map { "\(ByteFormatting.format($0.usedBytes)) / \(ByteFormatting.format($0.totalBytes))" } ?? topology.currentCapacity.statusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(topology.externals) { volume in
                    HStack {
                        Text("\(volume.name) — \(volume.capacity.applyingFreshness(maxAge: DiskTopologyService.capacityFreshness).availableValue.map { "\(ByteFormatting.format($0.usedBytes)) / \(ByteFormatting.format($0.totalBytes))" } ?? volume.capacity.applyingFreshness(maxAge: DiskTopologyService.capacityFreshness).statusLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if volume.isEjectable {
                            Button {
                                topology.eject(mountPath: volume.mountPath)
                            } label: {
                                Image(systemName: "eject")
                            }
                            .buttonStyle(.plain)
                            .help("Eject \(volume.name)")
                        }
                    }
                }
            }
            Section("Scan Summary") {
                Text("Target: \(state.scanTargetName)").font(.caption)
                if let last = state.lastScanDate {
                    Text("Last scan: \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                if coordinator.staleCache {
                    Text("Results may be outdated").font(.caption).foregroundStyle(.orange)
                }
                if let root = state.scanRoot {
                    Text("\(root.fileCount.formatted()) files · \(root.sizeString)").font(.caption).foregroundStyle(.secondary)
                    if !state.skippedPaths.isEmpty {
                        Text("\(state.skippedPaths.count) folders unreadable").font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text("No scan yet").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Section {
                Button {
                    state.showCleanup = true
                } label: {
                    Label("\(state.cleanupItems.count) items · \(state.cleanupSizeSummary)", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Cleanup Queue")
            }
        }
    }

    /// Sidebar row that jumps to the Folders tab. Uses a real `Button` (not a
    /// bare `Label`) because the sidebar is a `List(selection:)`: an untagged
    /// `Label` is selectable-looking but does nothing on click.
    private func favoriteShortcut(_ title: String, symbol: String) -> some View {
        Button {
            state.sidebarTab = .folders
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption)
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail content per tab + scan phase

    @ViewBuilder
    private var detailContent: some View {
        if !searchKey.query.isEmpty {
            GlobalSearchResultsView(
                query: searchKey.query, result: activeSearch == searchKey ? searchResult : .empty,
                isSearching: completedSearch != searchKey,
                scanLabel: state.scanRoot == nil ? nil : (state.indexedScanLabel ?? state.scanTargetName),
                appsLoading: inventory.isScanning,
                incompleteIndex: state.scanPhase == .scanning || !state.skippedPaths.isEmpty ||
                    (state.scanRoot != nil && state.records.isEmpty) || state.records.count >= 1_000_000,
                onSelect: openSearchResult,
                onClear: { searchQuery = "" })
        } else if state.sidebarTab == .applications {
            ApplicationsView()
        } else if state.sidebarTab == .folders {
            FolderExplorerView()
        } else if state.scanPhase == .scanning {
            ScanProgressView()
        } else if state.scanPhase == .failed {
            ScanFailedView()
        } else if state.scanPhase == .idle && state.scanRoot == nil {
            EmptyState(
                symbol: "magnifyingglass",
                title: "Ready to Scan",
                message: "Select a target and start scanning to see where your disk space is going. Or drag a folder onto this window.",
                actionTitle: "Start Scan (⌘R)",
                action: { state.startScan() }
            )
        } else {
            Group {
                switch state.sidebarTab {
                case .explore:
                VStack(spacing: 0) {
                    OverviewStrip()
                        .environmentObject(state)
                        .environmentObject(topology)
                    HStack(spacing: DesignTokens.Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.exploreView.title)
                                .font(.headline)
                            Text(state.exploreView.purpose)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(state.effectiveTopLevel.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(12)) { node in
                                Button {
                                    state.selectedNode = node
                                    state.inspectorVisible = true
                                } label: {
                                    Label("\(node.name) · \(node.sizeString)", systemImage: node.category.symbol)
                                }
                            }
                        } label: {
                            Label("Top folders", systemImage: "list.bullet")
                        }
                        .help("Quickly inspect the 12 largest top-level folders")
                        Menu {
                            ForEach(AppState.ExploreView.allCases, id: \.self) { view in
                                Button {
                                    state.exploreView = view
                                } label: {
                                    Label(view.title, systemImage: state.exploreView == view ? "checkmark" : view.symbol)
                                }
                            }
                        } label: {
                            Label("All 12 views", systemImage: "square.grid.2x2")
                        }
                        .help("Choose one of 12 disk visualizations")
                    }
                    .padding(.horizontal, DesignTokens.Space.m)
                    .padding(.top, DesignTokens.Space.s)
                    // 12-view switcher lives here (not the toolbar — a 12-segment
                    // control doesn't fit window chrome at 1100pt).
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignTokens.Space.xs) {
                            ForEach(AppState.ExploreView.allCases, id: \.self) { view in
                                Button {
                                    withAnimation(reduceMotion ? nil : DesignTokens.Motion.navigation) {
                                        state.exploreView = view
                                    }
                                } label: {
                                    Label(view.title, systemImage: view.symbol)
                                        .font(.caption)
                                        .padding(.horizontal, DesignTokens.Space.s)
                                        .padding(.vertical, DesignTokens.Space.xs)
                                        .background(state.exploreView == view ? Color.accentColor : Color.secondary.opacity(0.08))
                                        .foregroundStyle(state.exploreView == view ? .white : .primary)
                                        .clipShape(.rect(cornerRadius: DesignTokens.Radius.s))
                                }
                                .buttonStyle(.plain)
                                .help(view.purpose)
                                .accessibilityAddTraits(state.exploreView == view ? [.isSelected] : [])
                            }
                        }
                        .padding(.horizontal, DesignTokens.Space.m)
                        .padding(.vertical, DesignTokens.Space.xs)
                    }
                    Divider()
                    Group {
                        switch state.exploreView {
                        case .treemap: TreemapView()
                        case .sunburst: SunburstView()
                        case .flame: FlameView()
                        case .bubbles: BubblesView()
                        case .mindMap: MindMapView()
                        case .topSizes: TopSizesView()
                        case .ageMap: AgeMapView()
                        case .folderGrid: FolderGridView()
                        case .radial: RadialView()
                        case .icicle: IcicleView()
                        case .treelist: TreelistView()
                        case .extCloud: ExtCloudView()
                        }
                    }
                    .id(state.scanRoot?.id)
                }
            case .duplicates: DuplicatesView()
            case .applications: ApplicationsView()
            case .monitor: MonitorView()
            case .snapshots: SnapshotsView()
            case .litterScore: LitterScoreView()
            case .forecast: DiskForecastView()
            case .simulator: WhatIfView()
            case .devCaches: DevCacheView()
            case .health: DiskHealthView()
            case .budgets: SpaceBudgetView()
            case .liveFeed: FileFeedView()
            case .lifecycle: AppLifecycleView()
            case .provenance: FileProvenanceView()
            case .compression: SmartCompressionView()
            case .containers: ContainerView()
            case .privacy: PrivacyView()
            case .photos: PhotoLibraryView()
            case .smartClean: SmartCleanView()
            case .storage: StorageView()
            case .folders: FolderExplorerView()
            case .developer: DeveloperWorkspaceView()
            case .pro3D: Pro3DCacheView()
            case .videoEditor: VideoEditorCacheView()
                }
            }
            .id(state.sidebarTab) // identity per tab: transition animates on switch
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
        }
    }

    private func openSearchResult(_ hit: GlobalSearchHit) {
        state.searchText = ""
        switch hit.kind {
        case .section:
            if let tab = AppState.SidebarTab(rawValue: hit.target) { state.sidebarTab = tab }
        case .visualization:
            if let view = AppState.ExploreView(rawValue: hit.target) {
                state.exploreView = view
                state.sidebarTab = .explore
            }
        case .application:
            if let app = inventory.apps.first(where: { $0.bundlePath == hit.target || $0.bundleID == hit.target }) {
                state.selectedApp = app
                if !app.bundlePath.isEmpty {
                    state.selectedNode = ScanNode(name: app.name, path: app.bundlePath,
                                                  sizeBytes: app.totalBytes, category: .applications,
                                                  fileCount: max(app.artifacts.count, 1))
                    state.inspectorVisible = true
                }
                state.sidebarTab = .applications
            }
        case .folder, .file:
            state.folderSearchDestination = hit.kind == .folder
                ? hit.target : URL(fileURLWithPath: hit.target).deletingLastPathComponent().path
            if hit.kind == .file {
                state.selectedNode = ScanNode(name: hit.title, path: hit.target,
                                              sizeBytes: hit.bytes ?? 0,
                                              category: hit.category ?? .other, fileCount: 1)
                state.inspectorVisible = true
            } else {
                state.selectedNode = nil
            }
            state.sidebarTab = .folders
        }
        searchQuery = ""
    }

    private var statusBar: some View {
        HStack {
            if let root = state.scanRoot {
                Text("\(root.fileCount.formatted()) files scanned · \(root.sizeString) mapped in \(String(format: "%.1f", state.scanElapsed))s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("No scan yet").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if coordinator.phase != .complete {
                Text(coordinator.currentJobName.isEmpty ? "Preparing…" : coordinator.currentJobName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let node = state.selectedNode {
                Text("Selection: \(node.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.xs)
    }
}

// MARK: - Overview strip: live disk widget on the Explore tab (all real data)

private struct OverviewStrip: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var topology: DiskTopologyService

    @ViewBuilder
    private var diskRing: some View {
        if let capacity = topology.currentCapacity.availableValue {
            let percent = capacity.usedPercent
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: percent / 100)
                    .stroke(percent > 90 ? Color.red : percent > 75 ? Color.orange : Color.green,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent))")
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
            .frame(width: 46, height: 46)
            .accessibleProgress(value: percent / 100,
                label: "Disk usage: \(ByteFormatting.format(capacity.usedBytes)) used of \(ByteFormatting.format(capacity.totalBytes))")
        } else {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                Text("—").font(.caption2)
            }
            .frame(width: 46, height: 46)
            .accessibilityLabel("Disk usage: \(topology.currentCapacity.statusLabel)")
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            // Disk usage ring.
            HStack(spacing: DesignTokens.Space.s) {
                diskRing
                VStack(alignment: .leading, spacing: 1) {
                    Text(topology.dataVolumeName).font(.caption.weight(.semibold))
                    Text(topology.currentCapacity.availableValue.map { "\(ByteFormatting.format($0.freeBytes)) free" } ?? topology.currentCapacity.statusLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let date = topology.currentCapacity.measuredAt {
                        Text("Measured \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Divider().frame(height: 34)
            // Largest folder from the real scan.
            if let biggest = state.effectiveTopLevel.max(by: { $0.sizeBytes < $1.sizeBytes }), biggest.sizeBytes > 0 {
                stat(icon: "folder.fill", tint: biggest.category.color,
                     label: "Biggest", value: "\(biggest.name) · \(biggest.sizeString)")
            }
            // Reclaimable (staged queue or cleanable categories).
            if let root = state.scanRoot {
                let cleanable = root.children
                    .filter { $0.category == .caches || $0.category == .logs || $0.category == .stale }
                    .reduce(Int64(0)) { $0 + $1.sizeBytes }
                stat(icon: "sparkles", tint: .purple,
                     label: "Cleanable", value: ByteFormatting.format(cleanable))
            }
            // Last scan freshness.
            if let last = state.lastScanDate {
                stat(icon: "clock.arrow.circlepath", tint: .blue,
                     label: "Last scan", value: last.formatted(.relative(presentation: .named)))
            }
            Spacer()
            // Quick actions.
            HStack(spacing: DesignTokens.Space.s) {
                Button {
                    state.sidebarTab = .smartClean
                } label: {
                    Label("Smart Clean", systemImage: "wand.and.stars")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    state.showCleanup = true
                } label: {
                    Label("Queue (\(state.cleanupItems.count))", systemImage: "trash")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(state.cleanupItems.isEmpty)
            }
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
        .background(.quaternary.opacity(0.35))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func stat(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
            }
        }
        .help(value)
    }
}

// MARK: - §34 In-app notification banner (auto-dismiss 8s)

private struct NotificationBannerView: View {
    @EnvironmentObject var state: AppState
    let banner: AppState.Banner

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(banner.message)
                .font(.callout)
            Spacer()
            Button(banner.actionTitle) {
                switch banner.actionTitle {
                case "Show Trash": state.showTrashInFinder()
                case "Activate": state.showLicense = true
                case "Details": state.sidebarTab = .snapshots
                default: state.banner = nil
                }
            }
            .buttonStyle(.link)
            .font(.callout)
            Button {
                state.banner = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
        .background(.background)
        .onAppear { state.dismissBannerAfterDelay() }
    }
}

// MARK: - Inspector (§13 file/folder + §14 application)

private struct InspectorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
                HStack {
                    Text("Inspector").font(.headline)
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : DesignTokens.Motion.navigation) {
                            state.inspectorVisible = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Close Inspector")
                    .accessibilityLabel("Close Inspector")
                }
                if let node = state.selectedNode {
                    HStack(spacing: DesignTokens.Space.s) {
                        Image(systemName: node.category.symbol)
                            .font(.title)
                            .foregroundStyle(node.category.color)
                        VStack(alignment: .leading) {
                            Text(node.name).font(.title3.weight(.semibold))
                            Text(node.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    specRow("Total Size", value: node.sizeString)
                    if node.isSyntheticAggregate {
                        Label("Grouped scan result, not a real folder. Open its parent to inspect individual files.", systemImage: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if node.isPartial {
                        Label("Size is a lower bound; some contents could not be measured.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if node.isCollapsed, let reason = node.collapseReason {
                        Text("▸ Collapsed: \(reason) — double-click to expand")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let physical = node.physicalBytes {
                        specRow("On Disk", value: physical.fileSizeString)
                        let saved = node.sizeBytes - physical
                        if saved > 0 {
                            specRow("APFS Savings", value: saved.fileSizeString)
                        }
                    }
                    specRow("Files", value: node.fileCount.formatted())
                    if let modified = node.modified {
                        specRow("Modified", value: modified.formatted(date: .abbreviated, time: .omitted))
                    }
                    specRow("Category", value: node.category.label)
                    if let app = state.selectedApp, app.name == node.name || app.bundlePath == node.path {
                        // §14 real application breakdown.
                        specRow("Bundle Size", value: app.bundleBytes.fileSizeString)
                        specRow("Artifacts Size", value: app.artifactBytes.fileSizeString)
                        Text("Artifacts (\(app.artifacts.count))").font(.headline)
                        ForEach(app.artifacts.prefix(10), id: \.path) { artifact in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(shortInspectorPath(artifact.path)).font(.caption).lineLimit(1).truncationMode(.middle)
                                    Text(artifact.kind).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(artifact.bytes.fileSizeString)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button("Stage") {
                                    state.stage(source: "Inspector", path: artifact.path, bytes: artifact.bytes)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        HStack {
                            Button(app.isStale ? "Remove Leftovers" : "Uninstall…") {
                                state.uninstallApp = app
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                            Button("Clean Artifacts") {
                                for artifact in app.artifacts {
                                    state.stage(source: "Inspector", path: artifact.path, bytes: artifact.bytes)
                                }
                                state.showCleanup = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(app.artifacts.isEmpty)
                        }
                    }
                    if !node.children.isEmpty {
                        Text("Breakdown (\(node.children.count) items)").font(.headline)
                        ForEach(node.children.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.id) { child in
                            HStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(child.category.color)
                                    .frame(width: 10, height: 10)
                                Text(child.name).font(.caption).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(child.sizeString)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedNode = child }
                            .help(child.path)
                        }
                    }
                    if node.isActionable {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile((node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                        }
                        .buttonStyle(.bordered)
                        Button("Stage for Cleanup") {
                            // Re-measure directories rather than present partial scan
                            // totals as a verified cleanup estimate.
                            state.stage(source: "Inspector", path: node.path,
                                        bytes: node.isPartial ? -1 : node.sizeBytes)
                        }
                        .accentCTA()
                    }
                } else {
                    VStack(spacing: DesignTokens.Space.m) {
                        Spacer()
                        Image(systemName: "square.dashed")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("App: None")
                            .font(.title3.weight(.semibold))
                        Text("— Select an item to see its detail")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(DesignTokens.Space.m)
        }
    }

    private func specRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func shortInspectorPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
