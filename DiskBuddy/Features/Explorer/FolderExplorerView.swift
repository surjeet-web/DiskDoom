import SwiftUI

// MARK: - Folder Explorer: drill-down directory browser (single-folder answers)

struct FolderExplorerView: View {
    @StateObject private var engine = FolderExplorerEngine()
    @EnvironmentObject var state: AppState

    @State private var customThresholdGB = 5.0
    @State private var inspectorNode: FolderNode?
    @State private var selectedIDs: Set<String> = []
    @State private var tableSort: [KeyPathComparator<FolderNode>] = []
    @AppStorage("folderTableShowItems") private var showItemsColumn = true
    @AppStorage("folderTableShowType") private var showTypeColumn = true
    @AppStorage("folderTableShowModified") private var showModifiedColumn = true
    @AppStorage("folderTableShowShare") private var showShareColumn = true

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if engine.isLoading && engine.measurement == nil {
                loadingView
            } else if let error = engine.error, engine.measurement == nil {
                errorView(error)
            } else {
                BreadcrumbBar(items: engine.breadcrumbPath, onSelect: { engine.navigate(to: $0.path) })
                summaryBar
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let evidence = engine.measurementState.applyingFreshness(maxAge: FolderMeasurementEngine.measurementTTL, now: context.date)
                    Text([evidence.statusLabel, evidence.source, evidence.measuredAt.map { $0.formatted(date: .abbreviated, time: .standard) }, evidence.reason].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Space.m)
                }
                if engine.isLoading { loadingOverlay }
                TimelineView(.periodic(from: .now, by: 1)) { _ in content }
            }
        }
        .task {
            guard engine.measurement == nil else { return }
            let destination = state.folderSearchDestination
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            state.folderSearchDestination = nil
            engine.navigate(to: destination)
        }
        .onChange(of: state.folderSearchDestination) { destination in
            guard let destination else { return }
            state.folderSearchDestination = nil
            engine.navigate(to: destination)
        }
        .sheet(item: $inspectorNode) { node in
            FolderInspectorSheet(node: node, engine: engine)
        }
        .onChange(of: engine.measurement) { _ in
            inspectorNode = nil
            selectedIDs.formIntersection(Set(engine.children.map(\.id)))
        }
        .onChange(of: engine.children.map(\.id)) { ids in selectedIDs.formIntersection(Set(ids)) }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal) {
        HStack(spacing: DesignTokens.Space.m) {
            HStack(spacing: DesignTokens.Space.xs) {
                Button { engine.goBack() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
                    .disabled(!engine.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                Button { engine.goForward() } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Forward")
                    .disabled(!engine.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                Button { engine.goUp() } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Parent folder")
                    .disabled(!engine.canGoUp)
                    .keyboardShortcut("u", modifiers: .command)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text(engine.currentPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 360)
            Spacer(minLength: DesignTokens.Space.m)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: Binding(
                    get: { engine.filterText },
                    set: { engine.setFilterText($0) }))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(width: 130)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            Menu {
                ForEach(engine.thresholdPresets) { preset in
                    Button {
                        engine.setThreshold(preset)
                    } label: {
                        HStack {
                            Text(preset.label)
                            if engine.thresholdBytes == preset.bytes {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Text("Custom")
                HStack {
                    Slider(value: $customThresholdGB, in: 0.1...100, step: 0.5)
                        .frame(width: 130)
                    Text("\(customThresholdGB, specifier: "%.1f") GB")
                        .monospacedDigit()
                }
                Button("Apply Custom Threshold") {
                    engine.setCustomThreshold(gb: customThresholdGB)
                }
            } label: {
                Label(engine.thresholdLabel, systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 140)
            Picker("", selection: Binding(
                get: { engine.sortBy },
                set: { tableSort = []; engine.setSort($0) })) {
                    ForEach(FolderExplorerEngine.SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            Toggle(isOn: Binding(
                get: { engine.showHidden },
                set: { engine.setShowHidden($0) })) {
                    Image(systemName: engine.showHidden ? "eye" : "eye.slash")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show hidden files")
            Button { engine.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("Refresh folder measurement")
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button { engine.showTreemap.toggle() } label: {
                Image(systemName: engine.showTreemap ? "list.bullet" : "square.grid.3x3.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(engine.showTreemap ? "Switch to List" : "Switch to Treemap")
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
        }
        .background(DesignTokens.Palette.panel)
    }

    // MARK: Summary

    private var summaryBar: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text(engine.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            // WHY: unreadable (permission-denied) folders contribute 0 bytes,
            // so the total above is only a lower bound — say so instead of
            // letting it read as a complete measurement.
            if engine.unreadableFolderCount > 0 {
                Text("· \(engine.unreadableFolderCount) folders unreadable")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Permission denied — these folders contribute no bytes, so the total is a lower bound")
            }
            Spacer()
            if !engine.topExtensions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(engine.topExtensions, id: \.self) { ext in
                        Button {
                            engine.setFilterExtension(engine.filterExtension == ext ? nil : ext)
                        } label: {
                            Text(".\(ext)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    engine.filterExtension == ext ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                                    in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.04))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if engine.showTreemap {
            FolderTreemap(
                nodes: engine.children,
                totalSize: engine.measurement?.totalSize ?? 1,
                onSelect: { engine.enterFolder($0) })
                .padding(DesignTokens.Space.m)
        } else {
            explorerList
        }
    }

    private var explorerList: some View {
        GeometryReader { geometry in
        ScrollView(.horizontal) {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text(selectedIDs.isEmpty ? "\(engine.children.count) visible items" : "\(selectedIDs.count) selected")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if !selectedIDs.isEmpty {
                        Button("Stage Selection…") { stageSelection() }
                            .buttonStyle(.bordered)
                        Button("Inspect") {
                            inspectorNode = engine.children.first { selectedIDs.contains($0.id) }
                        }.disabled(selectedIDs.count != 1)
                    }
                    Menu("Columns") {
                        if #available(macOS 14.4, *) {
                        Toggle("Items", isOn: $showItemsColumn)
                        Toggle("Type", isOn: $showTypeColumn)
                        Toggle("Modified", isOn: $showModifiedColumn)
                        Toggle("Parent Share", isOn: $showShareColumn)
                        } else {
                            Text("All columns shown · visibility options require macOS 14.4")
                        }
                    }
                }.padding(12)
                Group {
                if #available(macOS 14.4, *) {
                Table(engine.children, selection: $selectedIDs, sortOrder: $tableSort) {
                    TableColumn("Name", value: \.name) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc")
                            .lineLimit(1).help("\(node.path)\n\(node.provenanceDisplay)\n\(node.shareDisplay)")
                    }.width(min: 220, ideal: 280)
                    TableColumn("Size", value: \.size) { node in
                        Text(node.sizeDisplay).monospacedDigit()
                            .foregroundStyle(node.isUnreadable ? Color.orange : Color.primary)
                    }.width(min: 110, ideal: 150)
                    if showItemsColumn {
                        TableColumn("Items") { node in Text(node.childCountDisplay).monospacedDigit() }
                            .width(min: 80, ideal: 100)
                    }
                    if showTypeColumn {
                        TableColumn("Type") { node in
                            Text(node.isSymlink ? "Symbolic link" : node.isPackage ? "Package" : node.isDirectory ? "Folder" : node.fileExtension ?? "File")
                        }.width(min: 90, ideal: 120)
                    }
                    if showModifiedColumn {
                        TableColumn("Modified") { node in
                            Text(node.modifiedDisplay).lineLimit(1)
                        }.width(min: 110, ideal: 140)
                    }
                    if showShareColumn {
                        TableColumn("Parent Share") { node in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.shareDisplay).font(.caption.monospacedDigit())
                                if !node.isUnreadable && !node.parentIsPartial {
                                    ProgressView(value: min(1, max(0, node.percentageOfParent / 100)))
                                        .tint(DesignTokens.Palette.cyan)
                                }
                            }.padding(.vertical, 4)
                        }.width(min: 100, ideal: 130)
                    }
                }
                } else {
                    // Conditional TableColumnBuilder content requires 14.4.
                    // Ventura retains the complete native ledger, not a fake
                    // column-visibility control or a raised deployment target.
                    Table(engine.children, selection: $selectedIDs, sortOrder: $tableSort) {
                        TableColumn("Name", value: \.name) { node in
                            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc")
                                .lineLimit(1).help("\(node.path)\n\(node.provenanceDisplay)\n\(node.shareDisplay)")
                        }.width(min: 220, ideal: 280)
                        TableColumn("Size", value: \.size) { node in Text(node.sizeDisplay).monospacedDigit() }
                            .width(min: 110, ideal: 150)
                        TableColumn("Items") { node in Text(node.childCountDisplay).monospacedDigit() }
                            .width(min: 80, ideal: 100)
                        TableColumn("Type") { node in
                            Text(node.isSymlink ? "Symbolic link" : node.isPackage ? "Package" : node.isDirectory ? "Folder" : node.fileExtension ?? "File")
                        }.width(min: 90, ideal: 120)
                        TableColumn("Modified") { node in Text(node.modifiedDisplay).lineLimit(1) }
                            .width(min: 110, ideal: 140)
                        TableColumn("Parent Share") { node in Text(node.shareDisplay).font(.caption.monospacedDigit()) }
                            .width(min: 100, ideal: 130)
                    }
                }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if ids.count == 1, let node = engine.children.first(where: { ids.contains($0.id) }) {
                        contextMenu(for: node)
                    } else if !ids.isEmpty {
                        Button("Stage \(ids.count) items for review…") {
                            selectedIDs = ids
                            stageSelection()
                        }
                    }
                } primaryAction: { ids in
                    if ids.count == 1, let node = engine.children.first(where: { ids.contains($0.id) }) {
                        engine.enterFolder(node)
                    }
                }
                .onChange(of: selectedIDs) { ids in engine.selectedNode = engine.children.first { ids.contains($0.id) } }
                .onChange(of: tableSort) { order in
                    guard let first = order.first else { return }
                    // Sort the entire measured set BEFORE the engine's display
                    // limit, not just the already-truncated visible rows.
                    if first.keyPath == \FolderNode.name {
                        engine.setSort(first.order == .forward ? .nameAscending : .nameDescending)
                    } else if first.keyPath == \FolderNode.size {
                        engine.setSort(first.order == .forward ? .sizeAscending : .sizeDescending)
                    }
                }
            }
            if let node = inspectorNode, geometry.size.width >= 1000 {
                FolderInspectorPanel(node: node)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            }
        }
        .frame(width: max(640, geometry.size.width), height: geometry.size.height)
        }
        }
    }

    private func stageSelection() {
        for node in engine.children where selectedIDs.contains(node.id) {
            state.stage(source: "Folders", path: node.path,
                        bytes: node.isUnreadable || node.isPartial || node.evidence(node.size).availableValue == nil ? -1 : node.size)
        }
        state.showCleanup = true
    }

    // MARK: Context Menu (staging only — deletion happens in the queue)

    @ViewBuilder
    private func contextMenu(for node: FolderNode) -> some View {
        Button("Open in Finder") { engine.openInFinder(node.path) }
        Button("Open with Default App") { engine.openDefaultApp(node.path) }
        Divider()
        if node.isDirectory && !node.isPackage {
            Button("Drill Into This Folder") { engine.enterFolder(node) }
        }
        Button("Inspect Details") { inspectorNode = node }
        Divider()
        Button("Copy Path") { engine.copyPath(node.path) }
        // WHY: unreadable nodes have no measured size — copying or staging
        // their 0 would launder "unknown" into a definite number.
        Button("Copy Size") { engine.copySize(node.size) }
            .disabled(node.isUnreadable || node.isPartial || node.evidence(node.size).availableValue == nil)
        Divider()
        Button("Stage for Cleanup") {
            // -1 = let AppState measure on disk instead of trusting the
            // unreadable node's placeholder 0.
            state.stage(source: "Explorer", path: node.path, bytes: node.isUnreadable || node.isPartial || node.evidence(node.size).availableValue == nil ? -1 : node.size)
            state.showCleanup = true
        }
    }

    // MARK: Loading / error

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(engine.loadingProgress)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingOverlay: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(engine.loadingProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.06))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack {
                Button("Retry") { engine.refresh() }
                    .buttonStyle(.borderedProminent)
                Button("Open Home") {
                    engine.navigate(to: FileManager.default.homeDirectoryForCurrentUser.path)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    FolderExplorerView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
