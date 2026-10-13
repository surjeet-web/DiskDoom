import SwiftUI

// MARK: - Icicle view: vertical partition columns (top = root, downward = deeper)

struct IcicleView: View {
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

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if !drillPath.isEmpty {
                PageHeader(
                    title: "Icicle",
                    segments: crumbs,
                    canGoBack: true,
                    onBack: { drillPath.removeLast() },
                    fallback: { drillPath.removeAll() })
            }
            GeometryReader { proxy in
                VStack(spacing: 3) {
                    ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                        HStack(spacing: 2) {
                            ForEach(layer, id: \.id) { node in
                                let frac = CGFloat(node.sizeBytes) / CGFloat(max(root.sizeBytes, 1))
                                Button {
                                    state.selectedNode = node
                                } label: {
                                    VStack(spacing: 1) {
                                        Text(node.name)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(node.sizeString)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(node.category.color.opacity(state.selectedNode?.id == node.id ? 1 : 0.8))
                                    .clipShape(.rect(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(state.selectedNode?.id == node.id ? .white : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(10, (proxy.size.width - CGFloat(layer.count - 1) * 2) * frac))
                                .help(node.tooltip)
                                .accessibilityLabel("Select \(node.name), \(node.sizeString)")
                                .contextMenu {
                                    if !node.children.isEmpty {
                                        Button("Open folder") { drillPath.append(node) }
                                    } else if node.isCollapsed {
                                        Button("Index folder") { state.expandNode(path: node.path) }
                                    }
                                }
                            }
                        }
                        // max(10, ...): on a short window the raw quotient goes
                        // negative and SwiftUI traps on the negative frame height.
                        .frame(height: max(10, (proxy.size.height - CGFloat(layers.count - 1) * 3) / CGFloat(layers.count)))
                    }
                }
            }
            HStack {
                Text("\(root.path) · top-down depth partition")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Menu("Open folder") {
                    ForEach(root.children.filter { !$0.children.isEmpty }.sorted { $0.sizeBytes > $1.sizeBytes }) { node in
                        Button("\(node.name) · \(node.sizeString)") { drillPath.append(node) }
                    }
                }
                .disabled(!root.children.contains { !$0.children.isEmpty })
                .help("Keyboard-accessible folder drill-down")
            }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    IcicleView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
