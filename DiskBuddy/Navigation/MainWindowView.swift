import SwiftUI
import Combine

/// The supplied HTML's connected header/nav/workspace/inspector/footer grid.
/// Services, selection and native operations remain the application's own.
struct MainWindowView: View {
    private let prepareServices: Bool

    init(prepareServices: Bool = true) { self.prepareServices = prepareServices }
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var topology: DiskTopologyService
    @EnvironmentObject private var coordinator: LaunchCoordinator
    @EnvironmentObject private var inventory: AppInventoryService
    @EnvironmentObject private var gamification: GamificationEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("navigationExpanded") private var navigationExpanded = true
    @AppStorage("showXPRewards") private var showXPRewards = true
    @ObservedObject private var activity = ActivityCenter.shared
    @State private var showActivity = false
    @State private var showCoverage = false
    @State private var dropTargeted = false
    @State private var observedScanRootID: UUID?
    @State private var searchQuery = ""
    @State private var searchIsActive = false
    @State private var searchResult = GlobalSearchResult.empty
    @State private var activeSearch: SearchKey?
    @State private var completedSearch: SearchKey?
    @State private var appSearchRevision = 0
    @State private var requestedSearchInventory = false
    @State private var visualizationReset = 0
    @State private var lastStorageAlertID: UUID?
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

    private var hasContextInspector: Bool { state.sidebarTab == .explore || state.sidebarTab == .applications }

    var body: some View {
        GeometryReader { geometry in
            let metrics = CinematicMetrics(viewport: geometry.size, expanded: navigationExpanded,
                                           inspector: hasContextInspector && state.inspectorVisible)
            ScrollView(.vertical) {
                shell(metrics)
                    .frame(width: metrics.width, height: metrics.shellHeight)
                    .padding(.vertical, metrics.margin)
                    .frame(maxWidth: .infinity)
            }
            .background(CinematicStage())
        }
        .frame(minWidth: 820, minHeight: 640)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showCleanup) { CleanupQueueSheet().environmentObject(state) }
        .sheet(isPresented: $showActivity) { ActivityCenterView().environmentObject(state) }
        .sheet(item: $state.uninstallApp) { app in
            UninstallSheet(app: app).environmentObject(state).environmentObject(inventory)
        }
        .sheet(item: $state.quickLookNode) { node in QuickLookSheet(node: node).environmentObject(state) }
        .sheet(isPresented: $showCoverage) { coverageSheet }
        .overlay(alignment: .top) {
            if let celebration = gamification.currentCelebration {
                CelebrationBanner(celebration: celebration) { gamification.dismissCurrentCelebration() }
                    .transition(.opacity).zIndex(20)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showXPRewards, let reward = gamification.currentReward {
                XPRewardToast(reward: reward) { gamification.dismissCurrentReward() }
                    .padding(24).transition(.opacity).zIndex(19)
            }
        }
        .onAppear { if prepareServices { state.startupCheck() } }
        .onReceive(state.$scanRoot) { root in
            if let previous = observedScanRootID, previous != root?.id { state.selectedNode = nil }
            observedScanRootID = root?.id
        }
        .onReceive(inventory.$apps.dropFirst()) { _ in appSearchRevision &+= 1 }
        .onChange(of: state.sidebarTab) { _ in searchIsActive = false }
        .onChange(of: state.exploreView) { _ in searchIsActive = false }
        .onChange(of: searchQuery) { searchIsActive = !$0.isEmpty }
        .onChange(of: searchFocused) { if $0 { searchIsActive = true } }
        .onReceive(NotificationCenter.default.publisher(for: .diskDoomSearchRequested)) { _ in
            searchFocused = true; searchIsActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .diskDoomNotificationOpened)) { event in
            switch event.object as? String {
            case NotificationService.categoryScan: state.sidebarTab = .explore
            case NotificationService.categoryCleanup: state.showCleanup = true
            case NotificationService.categoryGamification: state.sidebarTab = .progress
            case NotificationService.categoryMonitor: state.sidebarTab = .dupMonitor
            default: state.sidebarTab = .storage
            }
        }
        .onReceive(activity.$notices.dropFirst()) { notices in
            guard let latest = notices.first, latest.category == NotificationService.categorySpaceAlert,
                  latest.id != lastStorageAlertID else { return }
            lastStorageAlertID = latest.id
            state.banner = AppState.Banner(message: "\(latest.title) · \(latest.body)", actionTitle: "Storage Map", persistent: true)
        }
        .task(id: searchKey) { await performSearch(searchKey) }
    }

    private func shell(_ metrics: CinematicMetrics) -> some View {
        VStack(spacing: 0) {
            masthead(metrics).frame(height: metrics.headerHeight)
            HStack(spacing: 0) {
                sidebar(metrics)
                    .padding(.leading, 4)
                    .frame(width: metrics.sidebar)
                VStack(spacing: 0) {
                    workspace(compact: metrics.compact)
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.bodyHeight)
                    if metrics.stacked && metrics.inspector {
                        CinematicInspectorView(compact: true, stacked: true)
                            .frame(height: metrics.stackedInspectorHeight)
                    }
                }
                if metrics.inspectorWidth > 0 {
                    CinematicInspectorView(compact: metrics.compact)
                        .padding(.trailing, 3)
                        .frame(width: metrics.inspectorWidth)
                }
            }
            CinematicFooterBar(compact: metrics.compact, onActivity: { showActivity = true })
                .frame(height: metrics.footerHeight)
        }
        .background(CinematicShellBacking())
        .overlay { if !metrics.stacked { CinematicMountingDetails(compact: metrics.compact) } }
    }

    private func masthead(_ metrics: CinematicMetrics) -> some View {
        HStack(spacing: 0) {
            HStack {
                // Window traffic lights remain real macOS controls, never
                // decorative red/yellow/green circles pretending to work.
                Spacer()
                Button { navigationExpanded.toggle() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 18))
                }
                .buttonStyle(.plain).frame(width: 38, height: 38)
                .accessibilityLabel("Toggle navigation").help("Toggle navigation")
                Spacer().frame(width: metrics.compact ? 12 : 24)
            }
            .frame(width: metrics.sidebar)
            if !metrics.stacked {
                GeometryReader { geometry in
                    ZStack(alignment: .topTrailing) {
                        CinematicTelemetry().padding(.top, 26).padding(.leading, 7)
                            .frame(width: geometry.size.width * 0.52, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        scanControl(compact: metrics.compact)
                            .frame(width: max(170, geometry.size.width * 0.47), height: 78)
                            .padding(.trailing, 9)
                    }
                }
            }
            HStack(spacing: 10) {
                if metrics.stacked {
                    Button { scanAction() } label: { Image(systemName: state.scanPhase == .scanning ? "stop.fill" : "arrow.clockwise") }
                        .buttonStyle(CinematicIconButtonStyle())
                        .accessibilityLabel(state.scanPhase == .scanning ? "Cancel Scan" : "Scan")
                }
                searchField
                HStack(spacing: 3) {
                    Button { state.inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(CinematicIconButtonStyle(selected: state.inspectorVisible && hasContextInspector))
                        .disabled(!hasContextInspector).accessibilityLabel("Toggle inspector").help("Toggle inspector (⇧⌘I)")
                    Button { state.showCleanup = true } label: { Image(systemName: "trash") }
                        .buttonStyle(CinematicIconButtonStyle()).accessibilityLabel("Cleanup queue").help("Review cleanup queue")
                    Button {
                        state.saveSnapshotFromCurrentScan(label: "Manual"); state.sidebarTab = .snapshots
                    } label: { Image(systemName: "camera") }
                    .buttonStyle(CinematicIconButtonStyle()).disabled(state.scanRoot == nil)
                    .accessibilityLabel("Save snapshot").help("Save snapshot (⇧⌘S)")
                }
            }
            .padding(.top, metrics.compact ? 16 : 22)
            .padding(.horizontal, metrics.compact ? 12 : 20)
            .padding(.bottom, 10)
            .frame(width: metrics.stacked ? nil : metrics.searchWidth)
            .frame(maxWidth: metrics.stacked ? .infinity : nil)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(CinematicHeaderBacking().padding(.leading, -13))
        }
    }

    private func scanControl(compact: Bool) -> some View {
        Button(action: scanAction) {
            HStack(spacing: 13) {
                Image(systemName: state.scanPhase == .scanning ? "stop.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 43, height: 43)
                    .background(LinearGradient(colors: [Color(hex: 0xFFAD39), Color(hex: 0xFF4D11)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: DesignTokens.Palette.orange.opacity(0.5), radius: 9)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.scanPhase == .scanning ? "Cancel Scan" : "Scan").font(.system(size: 14, weight: .bold))
                    Text(state.scanPhase == .scanning ? "Stop the current disk scan" : "Scan your disk for space usage")
                        .font(.system(size: 10)).foregroundStyle(Color(hex: 0xACB3B9)).lineLimit(1)
                }
            }
            .padding(.horizontal, compact ? 20 : 28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(CinematicScanBacking())
        .accessibilityLabel(state.scanPhase == .scanning ? "Cancel Scan" : "Scan")
        .help("Scan your selected scope (⌘R)")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(Color(hex: 0x8CA2B2))
            TextField("Search folders, files…", text: $searchQuery)
                .accessibilityIdentifier("workspace.search")
                .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                .onSubmit { if activeSearch == searchKey, let hit = searchResult.hits.first { openSearchResult(hit) } }
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            } else {
                Text("⌘ K").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(hex: 0xB2C1CE)).fixedSize()
            }
        }
        .padding(.horizontal, 11).frame(height: 39)
        .background(Color(hex: 0x111922, opacity: 0.73), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color(hex: 0x607181, opacity: 0.45), lineWidth: 1) }
        .help("Search indexed files, folders, apps and commands (⌘K)")
    }

    private func sidebar(_ metrics: CinematicMetrics) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        CinematicBrand(compact: metrics.compact, iconOnly: !navigationExpanded)
                            .padding(.top, 21).padding(.bottom, 34)
                        navigationGroup("NAVIGATE", tabs: AppState.SidebarTab.primary, metrics: metrics)
                        Rectangle().fill(Color(hex: 0x46535B, opacity: 0.41)).frame(height: 1)
                            .padding(.horizontal, 5).padding(.top, 16).padding(.bottom, 17)
                        navigationGroup("INSIGHTS", tabs: AppState.SidebarTab.insights, metrics: metrics)
                        navigationGroup("MORE TOOLS", tabs: AppState.SidebarTab.tools, metrics: metrics).padding(.top, 18)
                        navigationGroup("PROFESSIONAL", tabs: AppState.SidebarTab.professional, metrics: metrics).padding(.top, 18)
                        if navigationExpanded {
                            Text("FAVORITES").font(.system(size: 10, weight: .bold)).tracking(1)
                                .foregroundStyle(Color(hex: 0xAAAFB4)).padding(.top, 18).padding(.bottom, 8)
                            favorite("/Applications", symbol: "app")
                            favorite("~/Downloads", symbol: "tray.and.arrow.down")
                            favorite("~/Library", symbol: "folder")
                            ForEach(topology.externals) { volume in
                                HStack {
                                    Text(volume.name).font(.caption).lineLimit(1)
                                    Spacer()
                                    if volume.isEjectable {
                                        Button { topology.eject(mountPath: volume.mountPath) } label: { Image(systemName: "eject") }
                                            .buttonStyle(.plain).accessibilityLabel("Eject \(volume.name)")
                                    }
                                }.padding(.vertical, 8)
                            }
                        }
                    }.padding(.horizontal, metrics.compact ? 11 : 17).padding(.bottom, 23)
                }
                .onChange(of: state.sidebarTab) { tab in reader.scrollTo(tab, anchor: .center) }
            }
            HStack {
                if navigationExpanded { Text("SYS / STORAGE").font(.system(size: 9, design: .monospaced)) }
                Spacer(minLength: 0)
                Button { state.showCleanup = true } label: {
                    Label("\(state.cleanupItems.count)", systemImage: "trash")
                }.buttonStyle(.plain).font(.system(size: 11))
                    .accessibilityLabel("Cleanup queue, \(state.cleanupItems.count) items")
            }
            .foregroundStyle(Color(hex: 0x8896A2)).padding(14)
            .overlay(alignment: .top) { Divider().padding(.horizontal, 17) }
        }
        .background(CinematicRegionBackground(region: .sidebar))
        .overlay(alignment: .trailing) { Color(hex: 0x53738B, opacity: 0.45).frame(width: 1) }
        .accessibilityElement(children: .contain).accessibilityLabel("Primary navigation")
    }

    private func navigationGroup(_ title: String, tabs: [AppState.SidebarTab], metrics: CinematicMetrics) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if navigationExpanded {
                Text(title).font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(Color(hex: 0xAAAFB4)).padding(.horizontal, 8).padding(.bottom, 8)
            }
            ForEach(tabs, id: \.self) { tab in
                Button { state.sidebarTab = tab; searchIsActive = false } label: {
                    HStack(spacing: 11) {
                        Image(systemName: tab.symbol).font(.system(size: 17)).frame(width: 18)
                            .foregroundStyle(state.sidebarTab == tab ? Color(hex: 0xFFB64F) : Color(hex: 0x119FFF))
                        if navigationExpanded {
                            Text(tab.title).font(.system(size: metrics.compact ? 11 : 12, weight: .bold)).lineLimit(1)
                            Spacer(minLength: 0)
                            if let shortcut = AppState.SidebarTab.primary.firstIndex(of: tab) {
                                Text("⌘\(shortcut + 1)").font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(state.sidebarTab == tab ? .white : Color(hex: 0x73808B))
                            }
                        }
                    }
                    .foregroundStyle(state.sidebarTab == tab ? .white : Color(hex: 0xCAD4DC))
                    .frame(maxWidth: .infinity, alignment: navigationExpanded ? .leading : .center)
                }
                .buttonStyle(CinematicNavigationStyle(selected: state.sidebarTab == tab, compact: metrics.compact))
                .accessibilityLabel(tab.title).accessibilityIdentifier("navigation.\(tab.rawValue)")
                .accessibilityAddTraits(state.sidebarTab == tab ? [.isSelected] : [])
                .help(tab.title).id(tab)
            }
        }
    }

    private func favorite(_ path: String, symbol: String) -> some View {
        Button {
            state.folderSearchDestination = (path as NSString).expandingTildeInPath
            state.sidebarTab = .folders; searchIsActive = false
        } label: { Label(path, systemImage: symbol).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7) }
            .buttonStyle(.plain)
    }

    private func workspace(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if let banner = state.banner { statusBanner(banner) }
            if state.limitedMode || !state.permissions.fdaGranted {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    Text("Limited access · some folders may be unreadable")
                    Spacer()
                    Button("Grant Access") { state.permissions.openPrivacySettings() }.buttonStyle(.link)
                }.font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.06))
            }
            detailContent(compact: compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CinematicRegionBackground(region: .workspace))
        .overlay(alignment: .leading) { Color(hex: 0x6C95B9, opacity: 0.35).frame(width: 1) }
        .overlay(alignment: .trailing) { Color(hex: 0x486576, opacity: 0.68).frame(width: 2) }
        .overlay { if dropTargeted { dropOverlay } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { return }
                DispatchQueue.main.async { state.startRealScan(root: url, label: url.lastPathComponent) }
            }
            return true
        }
    }

    @ViewBuilder private func detailContent(compact: Bool) -> some View {
        if searchIsActive && !searchKey.query.isEmpty {
            GlobalSearchResultsView(query: searchKey.query, result: activeSearch == searchKey ? searchResult : .empty,
                isSearching: completedSearch != searchKey,
                scanLabel: state.scanRoot == nil ? nil : (state.indexedScanLabel ?? state.scanTargetName),
                appsLoading: inventory.isScanning,
                incompleteIndex: state.scanPhase == .scanning || !state.skippedPaths.isEmpty ||
                    (state.scanRoot != nil && state.records.isEmpty) || state.records.count >= 1_000_000,
                onSelect: openSearchResult, onClear: { searchQuery = "" })
        } else if state.sidebarTab == .explore {
            exploreWorkspace(compact: compact)
        } else {
            switch state.sidebarTab {
            case .explore: EmptyView()
            case .duplicates: DuplicatesView()
            case .similar: SimilarFilesView()
            case .dupMonitor: DuplicateMonitorView()
            case .progress: GamificationView()
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
    }

    private func exploreWorkspace(compact: Bool) -> some View {
        VStack(spacing: 0) {
            CinematicOverviewStrip(compact: compact)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(AppState.ExploreView.allCases, id: \.self) { mode in
                        Button { state.exploreView = mode } label: {
                            Label(mode.title, systemImage: mode.symbol).labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(CinematicModeButtonStyle(selected: state.exploreView == mode))
                        .accessibilityAddTraits(state.exploreView == mode ? [.isSelected] : [])
                        .help(mode.purpose)
                    }
                }.padding(.horizontal, compact ? 11 : 20).padding(.vertical, 10)
            }
            .frame(height: 63)
            .background(LinearGradient(colors: [Color(hex: 0x0F151B), Color(hex: 0x11161D)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) { Color(hex: 0x26333D).frame(height: 1) }
            HStack(spacing: 10) {
                Button("STORAGE") { state.selectedNode = state.scanRoot; visualizationReset &+= 1 }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color(hex: 0xA1B4C4))
                    .help("Return to the current scan root")
                if let root = state.scanRoot {
                    Text("/ \(root.name)").font(.system(size: 11)).lineLimit(1).foregroundStyle(DesignTokens.Palette.text)
                }
                Spacer()
                Text("Click to select · Double-click to open").font(.system(size: 10)).foregroundStyle(Color(hex: 0x727E87)).lineLimit(1)
            }.padding(.horizontal, 26).frame(height: 34)
            Group {
                if state.scanPhase == .scanning { ScanProgressView() }
                else if state.scanPhase == .failed { ScanFailedView() }
                else if state.scanRoot == nil {
                    EmptyState(symbol: "internaldrive", title: "Ready to Scan",
                               message: "Choose a folder or disk to see its measured storage map. You can also drop a folder here.",
                               actionTitle: "Start Scan (⌘R)", action: { state.startScan() })
                } else { visualization }
            }
            .id("\(state.scanRoot?.id.uuidString ?? "empty")-\(visualizationReset)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var visualization: some View {
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

    private func scanAction() { state.scanPhase == .scanning ? state.cancelScan() : state.startScan() }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 14).strokeBorder(DesignTokens.Palette.cyan, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
            .background(DesignTokens.Palette.app.opacity(0.94))
            .overlay { Label("Drop folder to scan", systemImage: "folder.badge.plus").font(.title3) }.padding(24)
    }

    private func statusBanner(_ banner: AppState.Banner) -> some View {
        HStack(spacing: 10) {
            Image(systemName: banner.persistent ? "exclamationmark.triangle" : "info.circle").foregroundStyle(banner.persistent ? .orange : DesignTokens.Palette.cyan)
            Text(banner.message).font(.system(size: 12))
            Spacer()
            Button(banner.actionTitle) {
                switch banner.actionTitle {
                case "Show Trash": state.showTrashInFinder()
                case "Activate": state.showLicense = true
                case "Details": if banner.message.hasPrefix("Partial scan") { showCoverage = true } else { state.sidebarTab = .snapshots }
                case "Storage Map": state.sidebarTab = .storage; state.banner = nil
                default: state.banner = nil
                }
            }.buttonStyle(.link)
            Button { state.banner = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(DesignTokens.Palette.raised)
        .onAppear { state.dismissBannerAfterDelay() }
    }

    private var coverageSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scan Coverage").font(.title2.bold()); Spacer()
                Button("Done") { showCoverage = false }.keyboardShortcut(.cancelAction)
            }
            Text("\(state.skippedPaths.count) folders were unreadable. Mapped sizes are lower bounds.").foregroundStyle(.secondary)
            List(state.skippedPaths, id: \.self) { Label($0, systemImage: "lock").font(.callout.monospaced()).textSelection(.enabled) }
            Button("Open Full Disk Access Settings") { state.permissions.openPrivacySettings() }
        }.padding(25).frame(width: 620, height: 480).background(DesignTokens.Palette.panel)
    }

    private func performSearch(_ key: SearchKey) async {
        guard !key.query.isEmpty else { searchResult = .empty; activeSearch = key; completedSearch = key; return }
        if !requestedSearchInventory && inventory.apps.isEmpty && !inventory.isScanning {
            requestedSearchInventory = true; inventory.scan()
        }
        let apps = inventory.apps.map { SearchableApp(name: $0.name, bundleID: $0.bundleID,
            path: $0.bundlePath.isEmpty ? $0.bundleID : $0.bundlePath, bytes: $0.totalBytes) }
        let sections = AppState.SidebarTab.allCases.map { (id: $0.rawValue, title: $0.title) }
        let views = AppState.ExploreView.allCases.map { (id: $0.rawValue, title: $0.title) }
        let quick = GlobalSearch.find(query: key.query, records: [], root: nil, apps: apps, sections: sections, visualizations: views)
        guard !Task.isCancelled, searchKey == key else { return }
        activeSearch = key; searchResult = quick
        guard key.query.count >= 2 else { completedSearch = key; return }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let records = state.records, root = state.scanRoot
        let worker = Task.detached(priority: .userInitiated) {
            GlobalSearch.find(query: key.query, records: records, root: root, apps: apps, sections: sections, visualizations: views)
        }
        let found = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, searchKey == key else { return }
        searchResult = found; completedSearch = key
    }

    private func openSearchResult(_ hit: GlobalSearchHit) {
        state.searchText = ""
        switch hit.kind {
        case .section: if let tab = AppState.SidebarTab(rawValue: hit.target) { state.sidebarTab = tab }
        case .visualization:
            if let mode = AppState.ExploreView(rawValue: hit.target) { state.exploreView = mode; state.sidebarTab = .explore }
        case .application:
            if let app = inventory.apps.first(where: { $0.bundlePath == hit.target || $0.bundleID == hit.target }) {
                state.selectedApp = app
                if !app.bundlePath.isEmpty {
                    state.selectedNode = ScanNode(name: app.name, path: app.bundlePath, sizeBytes: app.totalBytes,
                                                  category: .applications, fileCount: max(app.artifacts.count, 1))
                    state.inspectorVisible = true
                }
                state.sidebarTab = .applications
            }
        case .folder, .file:
            state.folderSearchDestination = hit.kind == .folder ? hit.target : URL(fileURLWithPath: hit.target).deletingLastPathComponent().path
            if hit.kind == .file {
                state.selectedNode = ScanNode(name: hit.title, path: hit.target, sizeBytes: hit.bytes ?? 0,
                                              category: hit.category ?? .other, fileCount: 1)
            } else { state.selectedNode = nil }
            state.sidebarTab = .folders
        }
        searchQuery = ""; searchIsActive = false
    }
}

extension Notification.Name {
    static let diskDoomSearchRequested = Notification.Name("DiskDoom.searchRequested")
}
