import SwiftUI

// MARK: - Main window: sidebar (§36) + toolbar (§35) + inspector (§13/§14) + banners (§34) + drop zone (§33)

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var topology: DiskTopologyService
    @EnvironmentObject var coordinator: LaunchCoordinator
    @EnvironmentObject var inventory: AppInventoryService
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: DesignTokens.Layout.sidebarWidth)
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    if let banner = state.banner {
                        NotificationBannerView(banner: banner)
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
                            .animation(.easeOut(duration: 0.18), value: state.sidebarTab)
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
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(state.scanPhase == .scanning ? "Cancel" : "Scan") {
                    state.scanPhase == .scanning ? state.cancelScan() : state.startScan()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                TextField("Search", text: $state.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    state.inspectorVisible.toggle()
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
        .sheet(isPresented: $state.showLicense) {
            LicenseView().environmentObject(state.license)
        }
        .onAppear {
            state.startupCheck()
            Task {
                await topology.loadCapacity()
                await topology.loadExternals()
            }
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
                Text("\(topology.dataVolumeName) — \(ByteFormatting.format(max(0, topology.dataTotalBytes - topology.dataFreeBytes))) / \(ByteFormatting.format(topology.dataTotalBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(topology.externals) { volume in
                    HStack {
                        Text("\(volume.name) — \(ByteFormatting.format(volume.totalBytes - volume.freeBytes)) / \(ByteFormatting.format(volume.totalBytes))")
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
                    Label("\(state.cleanupItems.count) items · \(state.cleanupTotal.fileSizeString)", systemImage: "trash")
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
        if state.scanPhase == .scanning {
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
                    // 12-view switcher lives here (not the toolbar — a 12-segment
                    // control doesn't fit window chrome at 1100pt).
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignTokens.Space.xs) {
                            ForEach(AppState.ExploreView.allCases, id: \.self) { view in
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) {
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
                                .help("\(view.title) view")
                            }
                        }
                        .padding(.horizontal, DesignTokens.Space.m)
                        .padding(.vertical, DesignTokens.Space.xs)
                    }
                    Divider()
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
            .transition(AnyTransition.opacity.combined(with: .move(edge: .trailing)))
        }
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

    private var usedPercent: Double {
        let total = max(topology.dataTotalBytes, 1)
        return min(100, max(0, Double(total - topology.dataFreeBytes) / Double(total) * 100))
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            // Disk usage ring.
            HStack(spacing: DesignTokens.Space.s) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                        .frame(width: 46, height: 46)
                    Circle()
                        .trim(from: 0, to: usedPercent / 100)
                        .stroke(usedPercent > 90 ? Color.red : usedPercent > 75 ? Color.orange : Color.green,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 46, height: 46)
                    Text("\(Int(usedPercent))")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
                .accessibleProgress(
                    value: usedPercent / 100,
                    label: "Disk usage: \(ByteFormatting.format(max(0, topology.dataTotalBytes - topology.dataFreeBytes))) used of \(ByteFormatting.format(topology.dataTotalBytes))")
                VStack(alignment: .leading, spacing: 1) {
                    Text(topology.dataVolumeName).font(.caption.weight(.semibold))
                    Text("\(ByteFormatting.format(topology.dataFreeBytes)) free")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
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
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile((node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                    }
                        .buttonStyle(.bordered)
                    Button("Stage for Cleanup") {
                        state.stage(source: "Inspector", path: node.path, bytes: node.sizeBytes)
                    }
                    .accentCTA()
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
