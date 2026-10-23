import SwiftUI
import AppKit

// MARK: - §05 Explore: Treemap (squarified layout, real scan data)

struct TreemapView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []
    @State private var hoveredID: UUID? = nil

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
                        // Not a Button (see BubblesView): a Button consumes the
                        // single tap so the double-tap drill never fires.
                        TreemapCell(
                            node: cell.node,
                            rect: cell.rect,
                            isSelected: state.selectedNode?.id == cell.node.id,
                            isHovered: hoveredID == cell.node.id)
                            .onHover { hovering in
                                hoveredID = hovering ? cell.node.id : nil
                            }
                            .contextMenu {
                            if cell.node.isActionable {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile((cell.node.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                                }
                                Button("Quick Look") { state.quickLookNode = cell.node }
                            } else {
                                Text("Aggregated items — not a real folder").font(.caption)
                            }
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
                                if cell.node.isActionable {
                                    Button("Stage for Cleanup") {
                                        state.stage(source: "Treemap", path: cell.node.path, bytes: cell.node.sizeBytes)
                                    }
                                } else {
                                    Text("Aggregated items — not a real folder").font(.caption)
                                }
                                Divider()
                                Button("Info") { state.selectedNode = cell.node }
                            }
                            .onTapGesture(count: 2) {
                                if !cell.node.children.isEmpty {
                                    drillPath.append(cell.node)
                                } else if cell.node.isCollapsed {
                                    // Smart leaf: measure on demand, stay in place.
                                    state.expandNode(path: cell.node.path)
                                }
                            }
                            .onTapGesture {
                                state.selectedNode = cell.node
                            }
                    }
                }
            }
            HStack {
                Text("Click to inspect · double-click to open a folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CategoryLegend(categories: NodeCategory.allCases)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilitySummary)
        }
        .padding(DesignTokens.Space.m)
    }

    /// VoiceOver summary of the visualization (charts are opaque to it).
    private var accessibilitySummary: String {
        let sorted = currentNodes.sorted { $0.sizeBytes > $1.sizeBytes }
        let top = sorted.prefix(3)
            .map { "\($0.name) \($0.sizeString)" }
            .joined(separator: ", ")
        return "Treemap of \(currentNodes.count) folders. Largest: \(top.isEmpty ? "none" : top)"
    }

    private var breadcrumb: some View {
        PageHeader(
            title: "Treemap",
            segments: crumbs,
            canGoBack: !drillPath.isEmpty,
            onBack: { drillPath.removeLast() },
            fallback: { drillPath.removeAll() })
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

// MARK: - Single treemap cell

private struct TreemapCell: View {
    let node: ScanNode
    let rect: CGRect
    let isSelected: Bool
    let isHovered: Bool

    private var showLabel: Bool { rect.width > 60 && rect.height > 40 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [node.visualColor.opacity(isSelected || isHovered ? 0.98 : 0.88),
                                 node.visualColor.opacity(isSelected || isHovered ? 0.82 : 0.62)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? Color.white : Color.black.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )
            if showLabel {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: node.category.symbol)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                        Text(node.name)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(node.sizeString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                    if node.isCollapsed {
                        Text("▸ \(node.fileCount.formatted()) files · ×2 to expand")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(DesignTokens.Space.s)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(.rect(cornerRadius: 5))
        .contentShape(.rect(cornerRadius: 5))
        .help(node.tooltip) // native tooltip, 200ms hover per spec
        .padding(1)
        .scaleEffect(isHovered && !isSelected ? 0.99 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Squarified treemap layout
//
// Classic Bruls/Dick squarify: each strip is laid along the longer edge and
// grown while the worst aspect ratio improves — rectangles stay close to
// square instead of the thin slivers slice-and-dice produces.

enum TreemapLayout {
    struct Cell { let node: ScanNode; let rect: CGRect }

    static func layout(nodes: [ScanNode], in rect: CGRect) -> [Cell] {
        var items = nodes.filter { $0.sizeBytes > 0 }.sorted { $0.sizeBytes > $1.sizeBytes }
        guard !items.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let scale = (rect.width * rect.height) / CGFloat(totalBytes)

        var cells: [Cell] = []
        var bounds = rect
        // WHY the guards below: when the final strip exactly exhausts `bounds`
        // the remaining side becomes 0 → `span` 0 → `thickness = rowArea/span`
        // = +infinity → `CGRect(height: .infinity)` reaches SwiftUI and the
        // window traps ("Invalid frame dimension (infinity)") on real scans
        // whose sizes sum to the parent's total.
        while !items.isEmpty {
            guard bounds.width > 0, bounds.height > 0 else { break }
            // Each strip SPANS the shorter side; its thickness extends
            // along the longer side. Running strips the other way starves
            // the thickness of later (smaller) strips → slivers.
            let spanIsWidth = bounds.width <= bounds.height
            let span = spanIsWidth ? bounds.width : bounds.height
            var row: [(node: ScanNode, area: CGFloat)] = []
            var rowArea: CGFloat = 0

            while let next = items.first {
                let nextArea = CGFloat(next.sizeBytes) * scale
                let candidateArea = rowArea + nextArea
                let withNext = worstRatio(row.map(\.area) + [nextArea], totalArea: candidateArea, span: span)
                let without = row.isEmpty ? .infinity : worstRatio(row.map(\.area), totalArea: rowArea, span: span)
                if row.isEmpty || withNext <= without {
                    row.append((next, nextArea))
                    rowArea = candidateArea
                    items.removeFirst()
                } else {
                    break
                }
            }

            // Materialize the strip inside `bounds`.
            let thickness = rowArea / span
            guard span > 0, thickness > 0, thickness.isFinite else { break }
            var offset: CGFloat = 0
            for item in row {
                let length = thickness > 0 ? item.area / thickness : 0
                let cellRect = spanIsWidth
                    ? CGRect(x: bounds.minX + offset, y: bounds.minY, width: length, height: thickness)
                    : CGRect(x: bounds.minX, y: bounds.minY + offset, width: thickness, height: length)
                cells.append(Cell(node: item.node, rect: cellRect))
                offset += length
            }
            if spanIsWidth {
                // max(0, ...) because floating-point drift can push the remainder
                // slightly negative, which would feed SwiftUI a negative height.
                bounds = CGRect(x: bounds.minX, y: bounds.minY + thickness, width: bounds.width, height: max(0, bounds.height - thickness))
            } else {
                bounds = CGRect(x: bounds.minX + thickness, y: bounds.minY, width: max(0, bounds.width - thickness), height: bounds.height)
            }
        }
        return cells
    }

    /// Worst aspect ratio of a strip whose items sum to `totalArea`
    /// spanning a side of length `span` (thickness = totalArea / span).
    private static func worstRatio(_ areas: [CGFloat], totalArea: CGFloat, span: CGFloat) -> CGFloat {
        guard totalArea > 0, span > 0, !areas.isEmpty else { return .infinity }
        let thickness = totalArea / span
        var worst: CGFloat = 0
        for area in areas {
            let length = thickness > 0 ? area / thickness : 0
            guard length > 0 else { continue }
            worst = max(worst, max(thickness / length, length / thickness))
        }
        return worst
    }
}

#Preview {
    TreemapView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
