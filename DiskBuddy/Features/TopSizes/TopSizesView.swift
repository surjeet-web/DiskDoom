import SwiftUI

// MARK: - §10 Explore: Top Sizes (ranked table prototype, mock data)

struct TopSizesView: View {
    @EnvironmentObject var state: AppState
    @State private var limit = 50

    private var rows: [ScanNode] {
        var all: [ScanNode] = []
        func collect(_ node: ScanNode) {
            all.append(node)
            node.children.forEach(collect)
        }
        MockScanData.root.children.forEach(collect)
        let q = state.searchText.lowercased()
        let filtered = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) }
        return Array(filtered.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(limit))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("Top \(limit) by Size")
                    .font(.headline)
                Spacer()
                Picker("Show", selection: $limit) {
                    Text("Top 50").tag(50)
                    Text("Top 100").tag(100)
                    Text("All").tag(10_000)
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
                        .frame(width: 100 * CGFloat(node.sizeBytes) / CGFloat(MockScanData.totalBytes), height: 8)
                    Text(node.sizeString)
                        .font(.callout.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .background(state.selectedNode?.id == node.id ? Color.accentColor.opacity(0.12) : .clear)
                .onTapGesture { state.selectedNode = node }
                .contextMenu {
                    Button("Reveal in Finder") { }
                    Button("Quick Look") { state.quickLookNode = node }
                    Divider()
                    Button("Stage for Cleanup") {
                        state.stage(source: "TopSizes", path: node.path, bytes: node.sizeBytes)
                    }
                    Divider()
                    Button("Info") { state.selectedNode = node }
                }
            }
            .listStyle(.plain)
            Text("\(rows.count) items · \(rows.reduce(0) { $0 + $1.sizeBytes }.fileSizeString) total")
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
