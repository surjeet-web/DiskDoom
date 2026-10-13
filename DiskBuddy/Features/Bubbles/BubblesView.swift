import SwiftUI
import AppKit

// MARK: - §08 Explore: Bubbles (circle packing prototype, mock data)

struct BubblesView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []

    private var nodes: [ScanNode] {
        if let path = drillPath.last?.path,
           let current = state.currentScanNode(path: path) {
            return current.children
        }
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
                        VStack(spacing: 4) {
                            Button {
                                state.selectedNode = node
                            } label: {
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
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(node.name), \(node.sizeString)")
                            if diameter <= 60 {
                                Text(node.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 100)
                            }
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
                                .help("Index \(node.name) to browse its contents")
                            }
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
