import SwiftUI

// MARK: - Main window: sidebar (§36) + toolbar (§35) + inspector (§13/§14) + banners (§34) + drop zone (§33)

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var topology: DiskTopologyService
    @EnvironmentObject var coordinator: LaunchCoordinator
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
                    if state.limitedMode && state.scanPhase != .scanning {
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
            if state.sidebarTab == .explore && state.scanPhase == .done {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $state.exploreView) {
                        ForEach(AppState.ExploreView.allCases, id: \.self) { view in
                            Label(view.title, systemImage: view.symbol).tag(view)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minWidth: 420)
                }
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
            UninstallSheet(app: app).environmentObject(state)
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
            Section("Favorites") {
                Label("/Applications", systemImage: "app.badge").font(.caption)
                Label("~/Downloads", systemImage: "tray.and.arrow.down").font(.caption)
                Label("~/Library", systemImage: "folder").font(.caption)
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

    // MARK: Detail content per tab + scan phase

    @ViewBuilder
    private var detailContent: some View {
        if state.scanPhase == .scanning {
            ScanProgressView()
        } else if state.scanPhase == .failed {
            ScanFailedView()
        } else if state.scanPhase == .idle {
            EmptyState(
                symbol: "magnifyingglass",
                title: "Ready to Scan",
                message: "Select a target and start scanning to see where your disk space is going. Or drag a folder onto this window.",
                actionTitle: "Start Scan (⌘R)",
                action: { state.startScan() }
            )
        } else {
            switch state.sidebarTab {
            case .explore:
                switch state.exploreView {
                case .treemap: TreemapView()
                case .sunburst: SunburstView()
                case .flame: FlameView()
                case .bubbles: BubblesView()
                case .mindMap: MindMapView()
                case .topSizes: TopSizesView()
                case .ageMap: AgeMapView()
                case .folderGrid: FolderGridView()
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
            }
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
                    if node.category == .applications {
                        // §14 application extras.
                        specRow("Bundle Size", value: (node.sizeBytes / 3).fileSizeString)
                        specRow("Artifacts Size", value: (node.sizeBytes * 2 / 3).fileSizeString)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cleanup options").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("● Uninstall (all)").font(.caption)
                            Text("○ Clean artifacts only").font(.caption).foregroundStyle(.secondary)
                            Text("○ Select specific…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !node.children.isEmpty {
                        Text("Breakdown").font(.headline)
                        ForEach(node.children.prefix(7), id: \.id) { child in
                            HStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(child.category.color)
                                    .frame(width: 10, height: 10)
                                Text(child.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text(child.sizeString)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Reveal in Finder") { }
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
}
