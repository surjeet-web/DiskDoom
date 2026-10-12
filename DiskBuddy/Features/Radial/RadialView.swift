import SwiftUI

// MARK: - Radial view: concentric depth rings (static overview, tap selects)

struct RadialView: View {
    @EnvironmentObject var state: AppState

    private var root: ScanNode { state.effectiveRoot }
    private var ring1: [ScanNode] { root.children }
    private var ring2: [ScanNode] { root.children.flatMap(\.children) }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            GeometryReader { proxy in
                let size = proxy.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                // Clamp: a short/collapsed window makes the raw value negative,
                // and `Path.addArc` with a negative radius produces garbage paths.
                let outerR = max(4, min(size.width, size.height) / 2 - 8)
                Canvas { context, _ in
                    drawRing(context: &context, nodes: ring1, total: root.sizeBytes, center: center, inner: outerR * 0.3, outer: outerR * 0.62)
                    let ring2Total = ring1.reduce(0) { $0 + $1.sizeBytes }
                    drawRing(context: &context, nodes: ring2, total: max(ring2Total, 1), center: center, inner: outerR * 0.66, outer: outerR)
                    context.draw(
                        Text(root.sizeString).font(.title3.weight(.semibold)),
                        at: center)
                }
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { value in
                        select(at: value.location, center: center, mid: outerR * 0.64, outer: outerR)
                    }
                )
            }
            Text("Depth rings: top level → second level · tap to select")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Space.m)
    }

    private func drawRing(context: inout GraphicsContext, nodes: [ScanNode], total: Int64, center: CGPoint, inner: CGFloat, outer: CGFloat) {
        var start = -Double.pi / 2
        for node in nodes {
            let end = start + Double(node.sizeBytes) / Double(max(total, 1)) * 2 * .pi
            context.fill(
                Path { p in
                    p.addArc(center: center, radius: inner, startAngle: Angle(radians: start), endAngle: Angle(radians: end), clockwise: false)
                    p.addArc(center: center, radius: outer, startAngle: Angle(radians: end), endAngle: Angle(radians: start), clockwise: true)
                    p.closeSubpath()
                },
                with: .color(node.category.color.opacity(state.selectedNode?.id == node.id ? 1 : 0.8)))
            start = end
        }
    }

    private func select(at point: CGPoint, center: CGPoint, mid: CGFloat, outer: CGFloat) {
        let dx = point.x - center.x, dy = point.y - center.y
        let dist = hypot(dx, dy)
        let pool = dist < mid ? ring1 : dist <= outer ? ring2 : []
        guard !pool.isEmpty else { return }
        let total = dist < mid ? root.sizeBytes : max(ring1.reduce(0) { $0 + $1.sizeBytes }, 1)
        var angle = atan2(dy, dx)
        if angle < -Double.pi / 2 { angle += 2 * Double.pi }
        let normalized = (angle + Double.pi / 2).truncatingRemainder(dividingBy: 2 * Double.pi)
        var start = 0.0
        for node in pool {
            let end = start + Double(node.sizeBytes) / Double(total) * 2 * Double.pi
            if normalized >= start && normalized < end {
                state.selectedNode = node
                return
            }
            start = end
        }
    }
}

#Preview {
    RadialView().environmentObject(AppState())
        .frame(width: 700, height: 500)
}
