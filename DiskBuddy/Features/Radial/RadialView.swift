import SwiftUI

// MARK: - Radial view: parent-aligned depth rings and keyboard-accessible folder list

struct RadialView: View {
    @EnvironmentObject var state: AppState

    private var root: ScanNode { state.effectiveRoot }
    private var ring1: [ScanNode] { root.children }

    private struct Sector {
        let node: ScanNode
        let start: Double
        let end: Double
    }

    private var innerSectors: [Sector] {
        let total = Double(max(ring1.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }, 1))
        var start = -Double.pi / 2
        return ring1.map { node in
            let end = start + Double(max(0, node.sizeBytes)) / total * 2 * .pi
            defer { start = end }
            return Sector(node: node, start: start, end: end)
        }
    }

    private var outerSectors: [Sector] {
        innerSectors.flatMap { parent in
            var start = parent.start
            let children = parent.node.children
            let covered = children.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
            let total = Double(max(parent.node.sizeBytes, covered, 1))
            return children.map { child in
                let end = start + Double(max(0, child.sizeBytes)) / total * (parent.end - parent.start)
                defer { start = end }
                return Sector(node: child, start: start, end: end)
            }
        }
    }

    private var browseNodes: [ScanNode] {
        guard let selected = state.selectedNode,
              let parent = ring1.first(where: { $0.id == selected.id || $0.children.contains(where: { $0.id == selected.id }) }) else {
            return ring1
        }
        return parent.children.isEmpty ? ring1 : parent.children
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            GeometryReader { proxy in
                let size = proxy.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                // Clamp: a short/collapsed window makes the raw value negative,
                // and `Path.addArc` with a negative radius produces garbage paths.
                let outerR = max(4, min(size.width, size.height) / 2 - 8)
                Canvas { context, _ in
                    drawRing(context: &context, sectors: innerSectors, center: center, inner: outerR * 0.3, outer: outerR * 0.62)
                    drawRing(context: &context, sectors: outerSectors, center: center, inner: outerR * 0.66, outer: outerR)
                    context.draw(
                        Text(root.sizeString).font(.title3.weight(.semibold)),
                        at: center)
                }
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        select(at: value.location, center: center, radius: outerR)
                    }
                )
                .accessibilityHidden(true) // Equivalent visible buttons below expose every folder.
            }
            Text("Inner ring: folders · outer ring: their children. Select a folder to inspect it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Browse folders").font(.headline)
                Spacer()
                if browseNodes != ring1 {
                    Button("Top level") { state.selectedNode = nil }
                        .buttonStyle(.link)
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: DesignTokens.Space.s) {
                    ForEach(browseNodes) { node in
                        Button {
                            state.selectedNode = node
                            state.inspectorVisible = true
                        } label: {
                            Label("\(node.name) · \(node.sizeString)", systemImage: node.category.symbol)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .tint(node.category.color)
                        .accessibilityLabel("Inspect \(node.name), \(node.sizeString)")
                    }
                }
            }
            .frame(height: 38)
        }
        .padding(DesignTokens.Space.m)
    }

    private func drawRing(context: inout GraphicsContext, sectors: [Sector], center: CGPoint, inner: CGFloat, outer: CGFloat) {
        for sector in sectors where sector.end > sector.start {
            context.fill(
                Path { p in
                    p.addArc(center: center, radius: inner, startAngle: Angle(radians: sector.start), endAngle: Angle(radians: sector.end), clockwise: false)
                    p.addArc(center: center, radius: outer, startAngle: Angle(radians: sector.end), endAngle: Angle(radians: sector.start), clockwise: true)
                    p.closeSubpath()
                },
                with: .color(sector.node.category.color.opacity(state.selectedNode?.id == sector.node.id ? 1 : 0.8)))
        }
    }

    private func select(at point: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = point.x - center.x, dy = point.y - center.y
        let dist = hypot(dx, dy)
        let sectors = dist >= radius * 0.3 && dist <= radius * 0.62 ? innerSectors :
            dist >= radius * 0.66 && dist <= radius ? outerSectors : []
        var angle = atan2(dy, dx)
        if angle < -Double.pi / 2 { angle += 2 * Double.pi }
        if let sector = sectors.first(where: { angle >= $0.start && angle < $0.end }) {
            state.selectedNode = sector.node
            state.inspectorVisible = true
        }
    }
}

#Preview {
    RadialView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
