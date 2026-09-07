import SwiftUI

// MARK: - Treelist view: outline tree with size bars (Finder-like hybrid)

struct TreelistView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("Outline")
                    .font(.headline)
                Spacer()
                Text("Expand rows to drill · right-click for actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List {
                TreelistOutline(nodes: state.effectiveTopLevel)
            }
            .listStyle(.plain)
        }
        .padding(DesignTokens.Space.m)
    }
}

private struct TreelistOutline: View {
    let nodes: [ScanNode]

    var body: some View {
        ForEach(nodes) { node in
            if node.children.isEmpty {
                TreelistRow(node: node)
            } else {
                DisclosureGroup {
                    TreelistOutline(nodes: node.children)
                } label: {
                    TreelistRow(node: node)
                }
            }
        }
    }
}

private struct TreelistRow: View {
    @EnvironmentObject var state: AppState
    let node: ScanNode

    var body: some View {
        HStack(spacing: DesignTokens.Space.s) {
            Image(systemName: node.category.symbol)
                .foregroundStyle(node.category.color)
                .frame(width: 20)
            Text(node.name)
                .lineLimit(1)
            if node.isCollapsed {
                Text("▸ collapsed")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(node.category.color.opacity(0.7))
                .frame(width: 100 * CGFloat(node.sizeBytes) / CGFloat(max(state.effectiveRoot.sizeBytes, 1)), height: 8)
            Text(node.sizeString)
                .font(.callout.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .background(state.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : .clear)
        .onTapGesture { state.selectedNode = node }
        .onTapGesture(count: 2) {
            if node.isCollapsed {
                state.expandNode(path: node.path)
            }
        }
        .contextMenu {
            Button("Reveal in Finder") { }
            Button("Quick Look") { state.quickLookNode = node }
            Divider()
            if node.isCollapsed {
                Button("Expand (measure now)") { state.expandNode(path: node.path) }
                Divider()
            }
            Button("Stage for Cleanup") {
                state.stage(source: "Treelist", path: node.path, bytes: node.sizeBytes)
            }
            Divider()
            Button("Info") { state.selectedNode = node }
        }
    }
}

#Preview {
    TreelistView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
