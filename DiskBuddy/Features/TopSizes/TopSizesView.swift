import SwiftUI
import AppKit

// MARK: - §10 Explore: Top Sizes (ranked table from the completed scan)

struct TopSizesView: View {
    @EnvironmentObject var state: AppState
    @State private var limit = 50
    // WHY memoized: `rows`/`matchingCount` used to walk the whole scan tree,
    // filter, and sort inside `body`. @EnvironmentObject re-renders on EVERY
    // AppState publish (scan-progress ticks, selection, banner timers), so a
    // ~400k-node index cost hundreds of ms of main-actor work per render —
    // multi-second stalls when renders landed back to back. The pass now runs
    // only when `RowsKey` (every input to the derivation) changes.
    @State private var memo = DerivationMemo<Rows>()

    private struct Rows {
        let rows: [ScanNode]
        let matchingCount: Int
    }

    /// Complete input set of the derivation: if none of these changed, the
    /// displayed result cannot change either.
    private struct RowsKey: Hashable {
        let rootID: UUID? // a new scan / cached restore swaps the root
        let recordsCount: Int // subtree expansion splices into the index
        let searchText: String
        let limit: Int
    }

    private var derived: Rows {
        memo(key: RowsKey(rootID: state.scanRoot?.id,
                          recordsCount: state.records.count,
                          searchText: state.searchText,
                          limit: limit)) {
            var all: [ScanNode] = []
            func collect(_ node: ScanNode) {
                all.append(node)
                node.children.forEach(collect)
            }
            state.effectiveRoot.children.forEach(collect)
            let q = state.searchText.lowercased()
            let filtered = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
            return Rows(rows: Array(filtered.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit)),
                        matchingCount: filtered.count)
        }
    }

    private var rows: [ScanNode] { derived.rows }

    /// Total number of rows available before `limit` truncates (for "top N of M").
    private var matchingCount: Int { derived.matchingCount }

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

/// Memoizes a whole-index derivation keyed by every input it reads.
///
/// WHY: without this, `body` re-ran the full walk/filter/sort pass on every
/// AppState publish. At ~400k records each pass blocked the main actor for
/// hundreds of milliseconds, so routine interaction (typing, selection,
/// progress ticks) turned into multi-second main-thread stalls.
@MainActor
private final class DerivationMemo<Value> {
    private var entry: (key: AnyHashable, value: Value)?

    /// Returns the cached value when `key` is unchanged; otherwise runs
    /// `compute` once and stores the result under the new key.
    func callAsFunction<Key: Hashable>(key: Key, _ compute: () -> Value) -> Value {
        let erased = AnyHashable(key)
        if let entry, entry.key == erased { return entry.value }
        let fresh = compute()
        entry = (erased, fresh)
        return fresh
    }
}

#Preview {
    TopSizesView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
