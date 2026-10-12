import SwiftUI
import AppKit

// MARK: - §12 Explore: Folder Grid (LazyVGrid prototype, mock data)

struct FolderGridView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []

    private var current: ScanNode { drillPath.last ?? state.effectiveRoot }
    private var cells: [ScanNode] {
        current.children.isEmpty ? [current] : current.children.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            PageHeader(
                title: current.name,
                segments: crumbs,
                canGoBack: !drillPath.isEmpty,
                onBack: { drillPath.removeLast() },
                fallback: { drillPath = [state.effectiveRoot] })
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: DesignTokens.Space.m) {
                    ForEach(cells, id: \.id) { node in
                        // Not a Button: a Button swallows the single tap, so the
                        // `.onTapGesture(count: 2)` layered on it never fired and
                        // drill-down was unreachable. Plain view + contentShape
                        // lets both gestures coexist.
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: node.category.symbol)
                                    .font(.title2)
                                    .foregroundStyle(node.category.color)
                                Spacer()
                                if !node.children.isEmpty {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text(node.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(node.sizeString)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                            Text("\(node.fileCount.formatted()) files")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            GeometryReader { barProxy in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(node.category.color.opacity(0.7))
                                    .frame(width: barProxy.size.width * CGFloat(node.sizeBytes) / CGFloat(max(current.sizeBytes, 1)))
                            }
                            .frame(height: 6)
                        }
                        .padding(DesignTokens.Space.m)
                        .frame(height: 140)
                        .background(state.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                        .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                                .stroke(state.selectedNode?.id == node.id ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { state.selectedNode = node }
                        .onTapGesture(count: 2) {
                            if !node.children.isEmpty {
                                drillPath.append(node)
                            } else if node.isCollapsed {
                                state.expandNode(path: node.path)
                            }
                        }
                        .help(node.tooltip)
                        .contextMenu {
                            if node.isActionable {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile((node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                                }
                                Button("Quick Look") { state.quickLookNode = node }
                                Divider()
                                Button("Stage for Cleanup") {
                                    state.stage(source: "Grid", path: node.path, bytes: node.sizeBytes)
                                }
                            } else {
                                // Aggregated tail node: nothing to reveal and
                                // nothing safe to stage.
                                Text("Aggregated items — not a real folder")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            Text("\(current.path) · \(cells.count) directories · \(current.sizeString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }

    private var crumbs: [Crumb] {
        var result: [Crumb] = [.link(state.effectiveRoot.name) { drillPath = [state.effectiveRoot] }]
        for node in drillPath {
            if node.id == drillPath.last?.id {
                result.append(.here(node.name))
            } else {
                result.append(.link(node.name) {
                    while drillPath.last?.id != node.id { drillPath.removeLast() }
                })
            }
        }
        return result
    }
}

#Preview {
    FolderGridView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
