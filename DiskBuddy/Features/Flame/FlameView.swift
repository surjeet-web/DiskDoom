import SwiftUI

// MARK: - §07 Explore: Flame Graph (visual stack + tabular breakdown, mock data)

struct FlameView: View {
    @EnvironmentObject var state: AppState
    @State private var focus: ScanNode? = nil

    private var root: ScanNode { focus ?? MockScanData.root }

    private var layers: [[ScanNode]] {
        var result: [[ScanNode]] = [[root], root.children]
        let grandchildren = root.children.flatMap { $0.children }
        if !grandchildren.isEmpty { result.append(grandchildren) }
        return result
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if focus != nil {
                HStack {
                    Button("All") { focus = nil }
                        .buttonStyle(.link)
                    Text("▸").foregroundStyle(.tertiary)
                    Text(focus!.name)
                    Spacer()
                }
                .font(.caption)
            }
            GeometryReader { proxy in
                VStack(spacing: 4) {
                    ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                        HStack(spacing: 2) {
                            ForEach(layer, id: \.id) { node in
                                let frac = CGFloat(node.sizeBytes) / CGFloat(max(root.sizeBytes, 1))
                                Button {
                                    state.selectedNode = node
                                } label: {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(node.category.color.opacity(state.selectedNode?.id == node.id ? 1 : 0.8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(state.selectedNode?.id == node.id ? .white : .clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(8, (proxy.size.width - CGFloat(layer.count - 1) * 2) * frac), height: 28)
                                .help(node.tooltip)
                            }
                        }
                    }
                    Divider()
                    List(root.children.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.id) { node in
                        HStack {
                            Image(systemName: node.category.symbol)
                                .foregroundStyle(node.category.color)
                            Text(node.name).lineLimit(1)
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(node.category.color.opacity(0.7))
                                .frame(width: 120 * CGFloat(node.sizeBytes) / CGFloat(max(root.sizeBytes, 1)), height: 10, alignment: .leading)
                            Text(node.sizeString)
                                .font(.callout.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { state.selectedNode = node }
                        .onTapGesture(count: 2) {
                            if !node.children.isEmpty { focus = node }
                        }
                        .contextMenu {
                            Button("Focus (drill into)") {
                                if !node.children.isEmpty { focus = node }
                            }
                            Button("Stage for Cleanup") {
                                state.stage(source: "Flame", path: node.path, bytes: node.sizeBytes)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            Text("\(root.path) · \(root.sizeString) · \(root.children.count) subdirectories")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    FlameView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
