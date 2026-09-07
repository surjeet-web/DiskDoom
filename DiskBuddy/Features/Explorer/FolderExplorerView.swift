import SwiftUI

// MARK: - Folder Explorer: drill-down directory browser (single-folder answers)

struct FolderExplorerView: View {
    @StateObject private var engine = FolderExplorerEngine()
    @EnvironmentObject var state: AppState

    @State private var customThresholdGB = 5.0
    @State private var inspectorNode: FolderNode?

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
                if engine.isLoading { loadingOverlay }
                content
            }
        }
        .task {
            guard engine.measurement == nil else { return }
            engine.navigate(to: FileManager.default.homeDirectoryForCurrentUser.path)
        }
        .sheet(item: $inspectorNode) { node in
            FolderInspectorSheet(node: node, engine: engine)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Space.m) {
            HStack(spacing: DesignTokens.Space.xs) {
                Button { engine.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!engine.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                Button { engine.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!engine.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                Button { engine.goUp() } label: { Image(systemName: "chevron.up") }
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
                set: { engine.setSort($0) })) {
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
        .background(.ultraThinMaterial)
    }

    // MARK: Summary

    private var summaryBar: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text(engine.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        HSplitView {
            List(selection: Binding(
                get: { engine.selectedNode },
                set: { engine.selectedNode = $0 })) {
                    ForEach(Array(engine.children.enumerated()), id: \.element.id) { index, node in
                        FolderRow(
                            node: node,
                            rank: index + 1,
                            onTap: { engine.enterFolder(node) },
                            onInspect: { inspectorNode = node })
                            .tag(node)
                            .contextMenu { contextMenu(for: node) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            if let node = inspectorNode {
                FolderInspectorPanel(node: node)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            }
        }
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
        Button("Copy Size") { engine.copySize(node.size) }
        Divider()
        Button("Stage for Cleanup") {
            state.stage(source: "Explorer", path: node.path, bytes: node.size)
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
