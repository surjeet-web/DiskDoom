import SwiftUI

// MARK: - §09 Explore: Mind Map (column tree prototype, mock data)

struct MindMapView: View {
    @EnvironmentObject var state: AppState
    @State private var path: [ScanNode] = [MockScanData.root]

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("Click any node to focus · Double-click to drill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: DesignTokens.Space.xl) {
                        ForEach(Array(path.enumerated()), id: \.element.id) { depth, node in
                            mindColumn(node: node, depth: depth, totalWidth: proxy.size.width)
                        }
                        if let focused = path.last, !focused.children.isEmpty {
                            mindColumnChildren(of: focused)
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(DesignTokens.Space.m)
    }

    private func mindColumn(node: ScanNode, depth: Int, totalWidth: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Space.s) {
            mindNode(node, width: 170)
            if depth > 0 {
                Text("⌘↑: back · Esc: up one level")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func mindColumnChildren(of parent: ScanNode) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            ForEach(parent.children.sorted { $0.sizeBytes > $1.sizeBytes }, id: \.id) { child in
                mindNode(child, width: 190)
                    .onTapGesture { state.selectedNode = child }
                    .onTapGesture(count: 2) {
                        path.append(child)
                        state.selectedNode = child
                    }
                    .contextMenu {
                        Button("Focus") { path.append(child) }
                        Button("Stage for Cleanup") {
                            state.stage(source: "MindMap", path: child.path, bytes: child.sizeBytes)
                        }
                    }
            }
        }
    }

    private func mindNode(_ node: ScanNode, width: CGFloat) -> some View {
        Button {
            state.selectedNode = node
        } label: {
            HStack(spacing: DesignTokens.Space.s) {
                Image(systemName: node.category.symbol)
                    .foregroundStyle(node.category.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(node.sizeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !node.children.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(DesignTokens.Space.s)
            .frame(width: width)
            .background(state.selectedNode?.id == node.id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                    .stroke(state.selectedNode?.id == node.id ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .help(node.tooltip)
    }
}

#Preview {
    MindMapView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
