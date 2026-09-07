import SwiftUI

// MARK: - Icicle view: vertical partition columns (top = root, downward = deeper)

struct IcicleView: View {
    @EnvironmentObject var state: AppState
    @State private var focus: ScanNode? = nil

    private var root: ScanNode { focus ?? state.effectiveRoot }

    private var layers: [[ScanNode]] {
        var result: [[ScanNode]] = [[root], root.children]
        let grandchildren = root.children.flatMap { $0.children }
        if !grandchildren.isEmpty { result.append(grandchildren) }
        return result
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if focus != nil {
                PageHeader(
                    title: "Icicle",
                    segments: [.link("All") { focus = nil }, .here(focus!.name)],
                    canGoBack: true,
                    onBack: { focus = nil },
                    fallback: { focus = nil })
            }
            GeometryReader { proxy in
                VStack(spacing: 3) {
                    ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                        HStack(spacing: 2) {
                            ForEach(layer, id: \.id) { node in
                                let frac = CGFloat(node.sizeBytes) / CGFloat(max(root.sizeBytes, 1))
                                Button {
                                    state.selectedNode = node
                                } label: {
                                    VStack(spacing: 1) {
                                        Text(node.name)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(node.sizeString)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(node.category.color.opacity(state.selectedNode?.id == node.id ? 1 : 0.8))
                                    .clipShape(.rect(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(state.selectedNode?.id == node.id ? .white : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .frame(width: max(10, (proxy.size.width - CGFloat(layer.count - 1) * 2) * frac))
                                .help(node.tooltip)
                                .onTapGesture(count: 2) {
                                    if !node.children.isEmpty { focus = node }
                                }
                            }
                        }
                        .frame(height: (proxy.size.height - CGFloat(layers.count - 1) * 3) / CGFloat(layers.count))
                    }
                }
            }
            Text("\(root.path) · top-down depth partition · double-click to focus")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }
}

#Preview {
    IcicleView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
