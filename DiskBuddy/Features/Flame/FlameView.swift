import SwiftUI

// MARK: - §07 Explore: Flame Graph (visual stack + tabular breakdown)

struct FlameView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []

    private var root: ScanNode {
        guard let path = drillPath.last?.path else { return state.effectiveRoot }
        return state.currentScanNode(path: path) ?? state.effectiveRoot
    }

    private var crumbs: [Crumb] {
        var result: [Crumb] = [.link("All") { drillPath.removeAll() }]
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

    private var layers: [[ScanNode]] {
        var result: [[ScanNode]] = [[root], root.children]
        let grandchildren = root.children.flatMap { $0.children }
        if !grandchildren.isEmpty { result.append(grandchildren) }
        return result
    }

    /// Largest size among the rows the table actually lists. Normalizing bars
    /// against the whole disk instead makes every bar sub-pixel on real data.
    private var maxVisibleBytes: Int64 {
        max(layers.flatMap { $0 }.filter { $0.id != root.id }.map(\.sizeBytes).max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if !drillPath.isEmpty {
                PageHeader(
                    title: "Flame Graph",
                    segments: crumbs,
                    canGoBack: true,
                    onBack: { drillPath.removeLast() },
                    fallback: { drillPath.removeAll() })
            }
            GeometryReader { proxy in
                VStack(spacing: 4) {
                    ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                        HStack(spacing: 2) {
                            ForEach(layer, id: \.id) { node in
                                let frac = CGFloat(node.sizeBytes) / CGFloat(max(root.sizeBytes, 1))
                                Button {
                                    state.selectedNode = node
                                } label: {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(node.category.color.opacity(state.selectedNode?.id == node.id ? 1 : 0.8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(state.selectedNode?.id == node.id ? .white : .clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(8, (proxy.size.width - CGFloat(layer.count - 1) * 2) * frac), height: 28)
                                .help(node.tooltip)
                                .accessibilityLabel("Select \(node.name), \(node.sizeString)")
                            }
                        }
                    }
                    Divider()
                    List(root.children.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.id) { node in
                        HStack(spacing: DesignTokens.Space.s) {
                            Image(systemName: node.category.symbol)
                                .foregroundStyle(node.category.color)
                            Button(node.name) { state.selectedNode = node }
                                .buttonStyle(.plain)
                                .lineLimit(1)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(node.category.color.opacity(0.7))
                                .frame(width: 120 * CGFloat(node.sizeBytes) / CGFloat(maxVisibleBytes), height: 10, alignment: .leading)
                            Text(node.sizeString)
                                .font(.callout.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                            if !node.children.isEmpty {
                                Button("Open \(node.name)", systemImage: "chevron.right") {
                                    drillPath.append(node)
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Open \(node.name)")
                            } else if node.isCollapsed {
                                Button("Index \(node.name)", systemImage: "arrow.clockwise") {
                                    state.expandNode(path: node.path)
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Index this folder to browse its contents")
                            }
                        }
                        .contextMenu {
                            if !node.children.isEmpty {
                                Button("Open folder") { drillPath.append(node) }
                            } else if node.isCollapsed {
                                Button("Index folder") { state.expandNode(path: node.path) }
                            }
                            if node.isActionable {
                                Button("Stage for Cleanup") {
                                    state.stage(source: "Flame", path: node.path, bytes: node.sizeBytes)
                                }
                            } else {
                                Text("Aggregated items — not a real folder").font(.caption)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            Text("\(root.path) · \(root.sizeString) · \(root.children.count) subdirectories")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    FlameView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
