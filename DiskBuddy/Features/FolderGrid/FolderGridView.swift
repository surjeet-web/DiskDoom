import SwiftUI

// MARK: - §12 Explore: Folder Grid (LazyVGrid prototype, mock data)

struct FolderGridView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = [MockScanData.root.children[3]] // ~/Library per spec

    private var current: ScanNode { drillPath.last ?? MockScanData.root }
    private var cells: [ScanNode] {
        current.children.isEmpty ? [current] : current.children.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack(spacing: DesignTokens.Space.xs) {
                Button("Macintosh HD") { drillPath = [MockScanData.root] }
                    .buttonStyle(.link)
                ForEach(drillPath, id: \.id) { node in
                    Text("▸").foregroundStyle(.tertiary)
                    Button(node.name) {
                        while drillPath.last?.id != node.id { drillPath.removeLast() }
                    }
                    .buttonStyle(.link)
                }
                Spacer()
            }
            .font(.caption)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: DesignTokens.Space.m) {
                    ForEach(cells, id: \.id) { node in
                        Button {
                            state.selectedNode = node
                        } label: {
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
                        }
                        .buttonStyle(.plain)
                        .help(node.tooltip)
                        .onTapGesture(count: 2) {
                            if !node.children.isEmpty { drillPath.append(node) }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { }
                            Button("Quick Look") { state.quickLookNode = node }
                            Divider()
                            Button("Stage for Cleanup") {
                                state.stage(source: "Grid", path: node.path, bytes: node.sizeBytes)
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
}

#Preview {
    FolderGridView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
