import SwiftUI
import AppKit

// MARK: - §08 Explore: Bubbles (circle packing prototype, mock data)

struct BubblesView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []

    private var nodes: [ScanNode] {
        if let last = drillPath.last, !last.children.isEmpty { return last.children }
        return state.effectiveTopLevel
    }

    // NaN guard: `.max()` yields 0 (not nil) when every bubble is 0 bytes —
    // `?? 1` never fires — and `sqrt(0/0)` handed to `.frame(width:)` traps
    // at runtime right after a scan of an empty/permission-denied folder.
    private var maxBytes: Int64 { max(nodes.map(\.sizeBytes).max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if !drillPath.isEmpty {
                PageHeader(
                    title: "Bubbles",
                    segments: crumbs,
                    canGoBack: !drillPath.isEmpty,
                    onBack: { drillPath.removeLast() },
                    fallback: { drillPath.removeAll() })
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 16) {
                    ForEach(nodes.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.id) { node in
                        let diameter = 44 + 76 * sqrt(CGFloat(node.sizeBytes) / CGFloat(maxBytes))
                        // Not a Button: a Button swallows the single tap, so a
                        // `.onTapGesture(count: 2)` layered on it never fires and
                        // drill-down is unreachable. Plain view + contentShape
                        // lets both gestures coexist.
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(node.category.color.opacity(state.selectedNode?.id == node.id ? 1 : 0.8))
                                    .frame(width: diameter, height: diameter)
                                    .overlay(Circle().stroke(state.selectedNode?.id == node.id ? .white : .clear, lineWidth: 2))
                                if diameter > 60 {
                                    VStack(spacing: 0) {
                                        Text(node.name)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(node.sizeString)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    .frame(width: diameter - 12)
                                }
                            }
                            if diameter <= 60 {
                                Text(node.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 100)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.selectedNode = node }
                        .onTapGesture(count: 2) {
                            if !node.children.isEmpty { drillPath.append(node) }
                        }
                        .help(node.tooltip)
                        .contextMenu {
                            if node.isActionable {
                                Button("Stage for Cleanup") {
                                    state.stage(source: "Bubbles", path: node.path, bytes: node.sizeBytes)
                                }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile((node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                                }
                            } else {
                                Text("Aggregated items — not a real folder").font(.caption)
                            }
                        }
                    }
                }
                .padding()
            }
            Text("\(nodes.count) groups · \(state.effectiveRoot.sizeString) total")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
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
}

#Preview {
    BubblesView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
