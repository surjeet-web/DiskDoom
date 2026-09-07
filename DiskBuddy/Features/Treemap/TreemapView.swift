import SwiftUI

// MARK: - §05 Explore: Treemap (prototype slice-and-dice layout, mock data)

struct TreemapView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []

    private var currentNodes: [ScanNode] {
        if let last = drillPath.last, !last.children.isEmpty { return last.children }
        return state.effectiveTopLevel
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            if !drillPath.isEmpty {
                breadcrumb
            }
            GeometryReader { proxy in
                let cells = TreemapLayout.layout(nodes: currentNodes, in: CGRect(origin: .zero, size: proxy.size))
                ZStack(alignment: .topLeading) {
                    ForEach(cells, id: \.node.id) { cell in
                        TreemapCell(
                            node: cell.node,
                            isSelected: state.selectedNode?.id == cell.node.id,
                            showLabel: cell.rect.width > 60 && cell.rect.height > 40
                        )
                        .frame(width: cell.rect.width, height: cell.rect.height)
                        .offset(x: cell.rect.minX, y: cell.rect.minY)
                        .contextMenu {
                            Button("Reveal in Finder") { }
                            Button("Quick Look") { state.quickLookNode = cell.node }
                            Divider()
                            Button("Focus (re-root view here)") {
                                if !cell.node.children.isEmpty { drillPath.append(cell.node) }
                            }
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cell.node.path, forType: .string)
                            }
                            Button("Copy Size") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(cell.node.sizeString, forType: .string)
                            }
                            Divider()
                            Button("Stage for Cleanup") {
                                state.stage(source: "Treemap", path: cell.node.path, bytes: cell.node.sizeBytes)
                            }
                            Divider()
                            Button("Info") { state.selectedNode = cell.node }
                        }
                        .onTapGesture(count: 2) {
                            // Double-click: drill down (spec §05).
                            if !cell.node.children.isEmpty {
                                drillPath.append(cell.node)
                            }
                        }
                        .onTapGesture {
                            state.selectedNode = cell.node
                        }
                    }
                }
            }
            CategoryLegend(categories: NodeCategory.allCases)
        }
        .padding(DesignTokens.Space.m)
    }

    private var breadcrumb: some View {
        HStack(spacing: DesignTokens.Space.xs) {
            Button("All") { drillPath.removeAll() }
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
    }
}

// MARK: - Single treemap cell

private struct TreemapCell: View {
    let node: ScanNode
    let isSelected: Bool
    let showLabel: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(node.category.color.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? .white : .clear, lineWidth: 2)
                )
            if showLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(node.sizeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(DesignTokens.Space.s)
            }
        }
        .help(node.tooltip) // native tooltip, 200ms hover per spec
        .padding(1)
    }
}

// MARK: - Slice-and-dice layout (prototype stand-in for squarified treemap)

enum TreemapLayout {
    struct Cell { let node: ScanNode; let rect: CGRect }

    static func layout(nodes: [ScanNode], in rect: CGRect) -> [Cell] {
        let sorted = nodes.sorted { $0.sizeBytes > $1.sizeBytes }
        let total = sorted.reduce(0) { $0 + $1.sizeBytes }
        guard total > 0 else { return [] }
        return slice(sorted, total: total, in: rect, horizontal: rect.width >= rect.height)
    }

    private static func slice(_ nodes: [ScanNode], total: Int64, in rect: CGRect, horizontal: Bool) -> [Cell] {
        guard let first = nodes.first else { return [] }
        if nodes.count == 1 { return [Cell(node: first, rect: rect)] }
        let fraction = CGFloat(first.sizeBytes) / CGFloat(total)
        let (head, tail): (CGRect, CGRect)
        if horizontal {
            let w = rect.width * fraction
            head = CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
            tail = CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height)
        } else {
            let h = rect.height * fraction
            head = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
            tail = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
        }
        let rest = Array(nodes.dropFirst())
        let restTotal = total - first.sizeBytes
        return [Cell(node: first, rect: head)] + slice(rest, total: restTotal, in: tail, horizontal: !horizontal)
    }
}

#Preview {
    TreemapView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
