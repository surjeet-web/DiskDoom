import SwiftUI
import AppKit

// MARK: - §10 Explore: Top Sizes (ranked table from the completed scan)

struct TopSizesView: View {
    @EnvironmentObject var state: AppState
    @State private var limit = 50

    private var rows: [ScanNode] {
        var all: [ScanNode] = []
        func collect(_ node: ScanNode) {
            all.append(node)
            node.children.forEach(collect)
        }
        state.effectiveRoot.children.forEach(collect)
        let q = state.searchText.lowercased()
        let filtered = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
        return Array(filtered.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    /// Total number of rows available before `limit` truncates (for "top N of M").
    private var matchingCount: Int {
        var all: [ScanNode] = []
        func collect(_ node: ScanNode) {
            all.append(node)
            node.children.forEach(collect)
        }
        state.effectiveRoot.children.forEach(collect)
        let q = state.searchText.lowercased()
        return q.isEmpty ? all.count : all.filter { $0.name.lowercased().contains(q) }.count
    }

    /// Normalize bars against the largest *visible* row, not the whole disk:
    /// against the 1 TB root every real bar rounds to sub-pixel and the ranking
    /// is unreadable.
    private var maxVisibleBytes: Int64 { max(rows.map(\.sizeBytes).max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("Top \(min(limit, matchingCount)) of \(matchingCount) by Size")
                    .font(.headline)
                Spacer()
                Picker("Show", selection: $limit) {
                    Text("Top 50").tag(50)
                    Text("Top 100").tag(100)
                    // Labelled with its real cap: this is NOT "All", and calling it
                    // "All" silently hid the truncation on large scans.
                    Text("Top 10,000").tag(10_000)
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            List(Array(rows.enumerated()), id: \.element.id) { index, node in
                HStack(spacing: DesignTokens.Space.s) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Image(systemName: node.category.symbol)
                        .foregroundStyle(node.category.color)
                        .frame(width: 20)
                    Text(node.name).lineLimit(1)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(node.category.color.opacity(0.7))
                        .frame(width: 100 * CGFloat(node.sizeBytes) / CGFloat(maxVisibleBytes), height: 8)
                    Text(node.sizeString)
                        .font(.callout.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .background(state.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : .clear)
                .onTapGesture { state.selectedNode = node }
                .contextMenu {
                    if node.isActionable {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile((node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                        }
                        Button("Quick Look") { state.quickLookNode = node }
                        Divider()
                        Button("Stage for Cleanup") {
                            state.stage(source: "TopSizes", path: node.path, bytes: node.sizeBytes)
                        }
                    } else {
                        // The synthetic "Other (N items)" tail: no real path.
                        Text("Aggregated items — not a real folder").font(.caption)
                    }
                    Divider()
                    Button("Info") { state.selectedNode = node }
                }
            }
            .listStyle(.plain)
            Text("Showing \(rows.count) of \(matchingCount) items · \(rows.reduce(0) { $0 + $1.sizeBytes }.fileSizeString) shown · scan root \(state.effectiveRoot.sizeString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    TopSizesView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
