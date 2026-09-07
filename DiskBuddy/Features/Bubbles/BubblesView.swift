import SwiftUI

// MARK: - §08 Explore: Bubbles (circle packing prototype, mock data)

struct BubblesView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []

    private var nodes: [ScanNode] {
        if let last = drillPath.last, !last.children.isEmpty { return last.children }
        return state.effectiveTopLevel
    }

    private var maxBytes: Int64 { nodes.map(\.sizeBytes).max() ?? 1 }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if !drillPath.isEmpty {
                HStack {
                    Button("All") { drillPath.removeAll() }
                        .buttonStyle(.link)
                    ForEach(drillPath, id: \.id) { node in
                        Text("▸").foregroundStyle(.tertiary)
                        Text(node.name)
                    }
                    Spacer()
                }
                .font(.caption)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 16) {
                    ForEach(nodes.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.id) { node in
                        let diameter = 44 + 76 * sqrt(CGFloat(node.sizeBytes) / CGFloat(maxBytes))
                        Button {
                            state.selectedNode = node
                        } label: {
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
                        }
                        .buttonStyle(.plain)
                        .help(node.tooltip)
                        .onTapGesture(count: 2) {
                            if !node.children.isEmpty { drillPath.append(node) }
                        }
                        .contextMenu {
                            Button("Stage for Cleanup") {
                                state.stage(source: "Bubbles", path: node.path, bytes: node.sizeBytes)
                            }
                            Button("Reveal in Finder") { }
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
}

#Preview {
    BubblesView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
