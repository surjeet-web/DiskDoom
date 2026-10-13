import SwiftUI
import AppKit

// MARK: - Treelist view: outline tree with size bars (Finder-like hybrid)

struct TreelistView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("Outline")
                    .font(.headline)
                Spacer()
                Text("Expand rows to browse · Index opens collapsed folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List {
                TreelistOutline(
                    nodes: state.effectiveTopLevel,
                    // Bars normalize against the largest row actually on screen,
                    // not the whole disk — against a 1 TB root every real row
                    // rounds to a sub-pixel sliver and the ranking is unreadable.
                    maxVisibleBytes: max(state.effectiveTopLevel.map(\.sizeBytes).max() ?? 0, 1))
            }
            .listStyle(.plain)
        }
        .padding(DesignTokens.Space.m)
    }
}

private struct TreelistOutline: View {
    let nodes: [ScanNode]
    let maxVisibleBytes: Int64

    var body: some View {
        ForEach(nodes) { node in
            if node.children.isEmpty {
                TreelistRow(node: node, maxVisibleBytes: maxVisibleBytes)
            } else {
                DisclosureGroup {
                    TreelistOutline(nodes: node.children, maxVisibleBytes: maxVisibleBytes)
                } label: {
                    TreelistRow(node: node, maxVisibleBytes: maxVisibleBytes)
                }
            }
        }
    }
}

private struct TreelistRow: View {
    @EnvironmentObject var state: AppState
    let node: ScanNode
    let maxVisibleBytes: Int64

    var body: some View {
        HStack(spacing: DesignTokens.Space.s) {
            Image(systemName: node.category.symbol)
                .foregroundStyle(node.category.color)
                .frame(width: 20)
            Text(node.name)
                .lineLimit(1)
            if node.isCollapsed {
                Button("Index folder") { state.expandNode(path: node.path) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!node.isActionable)
                    .help("Index \(node.name) to show its contents")
            }
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(node.category.color.opacity(0.7))
                .frame(width: 100 * CGFloat(node.sizeBytes) / CGFloat(max(maxVisibleBytes, 1)), height: 8)
            Text(node.sizeString)
                .font(.callout.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .background(state.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : .clear)
        // Double-tap listed first so it can claim the second tap; ordering a
        // single tap ahead of it made drill/expand unreachable on real rows.
        .onTapGesture(count: 2) {
            if node.isCollapsed {
                state.expandNode(path: node.path)
            }
        }
        .onTapGesture { state.selectedNode = node }
        .contextMenu {
            if node.isActionable {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile((node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                }
                Button("Quick Look") { state.quickLookNode = node }
                Divider()
                if node.isCollapsed {
                    Button("Expand (measure now)") { state.expandNode(path: node.path) }
                    Divider()
                }
                Button("Stage for Cleanup") {
                    state.stage(source: "Treelist", path: node.path, bytes: node.sizeBytes)
                }
            } else {
                // Aggregated tail node: nothing to reveal and nothing safe to
                // stage — staging it would have queued its whole parent.
                Text("Aggregated items — not a real folder")
                    .font(.caption)
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
