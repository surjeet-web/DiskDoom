import SwiftUI

// MARK: - §06 Explore: Sunburst (prototype 2-ring Canvas, mock data)

struct SunburstView: View {
    @EnvironmentObject var state: AppState
    @State private var drillPath: [ScanNode] = []
    @State private var hoveredID: UUID? = nil

    private var root: ScanNode {
        if let last = drillPath.last { return last }
        return state.effectiveRoot
    }

    private var inner: [ScanNode] { root.children.isEmpty ? [root] : root.children }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            breadcrumb
            GeometryReader { proxy in
                let size = proxy.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outerR = min(size.width, size.height) / 2 - 8
                let innerR = outerR * 0.45
                let midR = outerR * 0.75
                Canvas { context, _ in
                    var start = -Double.pi / 2
                    for node in inner {
                        let frac = Double(node.sizeBytes) / Double(max(root.sizeBytes, 1))
                        let end = start + frac * 2 * Double.pi
                        // Inner segment.
                        context.fill(
                            Path { p in
                                p.addArc(center: center, radius: innerR, startAngle: Angle(radians: start), endAngle: Angle(radians: end), clockwise: false)
                                p.addArc(center: center, radius: midR, startAngle: Angle(radians: end), endAngle: Angle(radians: start), clockwise: true)
                                p.closeSubpath()
                            },
                            with: .color(node.category.color.opacity(node.id == hoveredID ? 1 : 0.85))
                        )
                        // Outer ring: children (or the node itself if leaf).
                        let outer = node.children.isEmpty ? [node] : node.children
                        let outerTotal = outer.reduce(0) { $0 + $1.sizeBytes }
                        var oStart = start
                        for child in outer {
                            let oFrac = Double(child.sizeBytes) / Double(max(outerTotal, 1)) * (end - start)
                            let oEnd = oStart + oFrac
                            context.fill(
                                Path { p in
                                    p.addArc(center: center, radius: midR, startAngle: Angle(radians: oStart), endAngle: Angle(radians: oEnd), clockwise: false)
                                    p.addArc(center: center, radius: outerR, startAngle: Angle(radians: oEnd), endAngle: Angle(radians: oStart), clockwise: true)
                                    p.closeSubpath()
                                },
                                with: .color(child.category.color.opacity(child.id == hoveredID ? 1 : 0.7))
                            )
                            oStart = oEnd
                        }
                        start = end
                    }
                    // Center label.
                    context.draw(
                        Text(root.sizeString).font(.title3.weight(.semibold)),
                        at: center
                    )
                }
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        handleTap(at: value.location, center: center, innerR: innerR, midR: midR, outerR: outerR)
                    }
                )
                // hoveredID was read by the fill color but never written, so the
                // hover highlight was dead code. Mirror handleTap's segment
                // resolution so hover highlights the same segment a click would.
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        hoveredID = hitID(at: location, center: center, innerR: innerR, midR: midR, outerR: outerR)
                    case .ended:
                        hoveredID = nil
                    }
                }
            }
            CategoryLegend(categories: NodeCategory.allCases)
        }
        .padding(DesignTokens.Space.m)
    }

    // MARK: Breadcrumb (spec §06)

    private var breadcrumb: some View {
        PageHeader(
            title: "Sunburst",
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

    // MARK: Tap → select (outer) / drill (inner), center → up

    private func handleTap(at point: CGPoint, center: CGPoint, innerR: CGFloat, midR: CGFloat, outerR: CGFloat) {
        let dx = point.x - center.x, dy = point.y - center.y
        let dist = hypot(dx, dy)
        if dist < innerR {
            // Center: zoom out one level.
            if !drillPath.isEmpty { drillPath.removeLast() }
            return
        }
        switch segment(at: point, center: center, midR: midR, outerR: outerR) {
        case .inner(let node):
            state.selectedNode = node
            if !node.children.isEmpty { drillPath.append(node) }
        case .outer(let child):
            state.selectedNode = child
        case .none:
            break
        }
    }

    /// Which drawn segment a point falls in. Shared by tap and hover so the
    /// highlight can never disagree with what a click selects.
    private enum Segment {
        case inner(ScanNode)
        case outer(ScanNode)
        case none
    }

    private func hitID(at point: CGPoint, center: CGPoint, innerR: CGFloat, midR: CGFloat, outerR: CGFloat) -> UUID? {
        switch segment(at: point, center: center, midR: midR, outerR: outerR) {
        case .inner(let node), .outer(let node): return node.id
        case .none: return nil
        }
    }

    private func segment(at point: CGPoint, center: CGPoint, midR: CGFloat, outerR: CGFloat) -> Segment {
        let dx = point.x - center.x, dy = point.y - center.y
        let dist = hypot(dx, dy)
        var angle = atan2(dy, dx)
        if angle < -Double.pi / 2 { angle += 2 * Double.pi }
        let normalized = (angle + Double.pi / 2).truncatingRemainder(dividingBy: 2 * Double.pi)
        var start = 0.0
        for node in inner {
            let frac = Double(node.sizeBytes) / Double(max(root.sizeBytes, 1))
            let end = start + frac * 2 * Double.pi
            if normalized >= start && normalized < end {
                if dist < midR {
                    return .inner(node)
                } else if dist <= outerR {
                    let outer = node.children.isEmpty ? [node] : node.children
                    let total = outer.reduce(0) { $0 + $1.sizeBytes }
                    var oStart = start
                    for child in outer {
                        let oEnd = oStart + Double(child.sizeBytes) / Double(max(total, 1)) * (end - start)
                        if normalized >= oStart && normalized < oEnd {
                            return .outer(child)
                        }
                        oStart = oEnd
                    }
                }
                return .none
            }
            start = end
        }
        return .none
    }
}

#Preview {
    SunburstView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
