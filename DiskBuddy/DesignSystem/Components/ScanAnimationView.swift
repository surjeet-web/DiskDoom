import SwiftUI

// MARK: - Disk scan animation (SwiftUI recreation of the scan SVG:
// rotating beam, capacity ticks, pulsing storage segments, discovery nodes)
//
// SMIL/SVG animation doesn't run natively in SwiftUI, so the motion is
// rebuilt with TimelineView + Canvas. Static frame when Reduce Motion is on.

struct ScanAnimationView: View {
    let size: CGFloat
    var segmentFractions: [Double] = [0.28, 0.22, 0.18, 0.14, 0.18]

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        if reduceMotion {
            Canvas { context, size in
                drawStatic(in: &context, size: size)
            }
            .frame(width: size, height: size)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    drawFrame(in: &context, size: size, time: t)
                }
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: Frame

    private func drawFrame(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 4

        drawOuterRing(in: &context, center: center, radius: radius, time: time)
        drawSegments(in: &context, center: center, radius: radius * 0.72, time: time)
        drawBeam(in: &context, center: center, radius: radius * 0.8, angle: time * (2 * .pi / 3.4))
        drawHub(in: &context, center: center, radius: radius * 0.22, time: time)
        drawPulse(in: &context, center: center, radius: radius * 0.72, time: time)
    }

    private func drawStatic(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 4
        drawOuterRing(in: &context, center: center, radius: radius, time: 0)
        drawSegments(in: &context, center: center, radius: radius * 0.72, time: 0)
        drawHub(in: &context, center: center, radius: radius * 0.22, time: 0)
    }

    private func drawOuterRing(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        // Capacity ticks (slow rotation).
        let tickCount = 12
        for i in 0..<tickCount {
            let base = Double(i) / Double(tickCount) * 2 * .pi + time * (2 * .pi / 12)
            let inner = radius - 5
            let p1 = CGPoint(x: center.x + CGFloat(cos(base)) * inner, y: center.y + CGFloat(sin(base)) * inner)
            let p2 = CGPoint(x: center.x + CGFloat(cos(base)) * radius, y: center.y + CGFloat(sin(base)) * radius)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path, with: .color(Color(red: 0.62, green: 0.81, blue: 0.94)), lineWidth: 1.2)
        }
        // Dashed orbit.
        var orbit = Path()
        orbit.addArc(center: center, radius: radius + 3, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        context.stroke(orbit, with: .color(Color(red: 0.78, green: 0.84, blue: 0.89).opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [1, 5]))
    }

    private func drawSegments(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        // Storage category arcs with staggered breathing opacity.
        let colors: [Color] = [
            Color(red: 0.22, green: 0.63, blue: 0.97),
            Color(red: 0.36, green: 0.72, blue: 0.98),
            Color(red: 0.49, green: 0.77, blue: 0.97),
            Color(red: 0.66, green: 0.85, blue: 0.97),
            Color(red: 0.96, green: 0.98, blue: 0.99),
        ]
        var start = -Double.pi / 2
        for (i, frac) in segmentFractions.enumerated() {
            let end = start + frac * 2 * .pi
            let breathe = 0.55 + 0.4 * sin(time * (2 * .pi / 3.2) + Double(i) * 0.8)
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: Angle(radians: start), endAngle: Angle(radians: end), clockwise: false)
            path.addArc(center: center, radius: radius * 0.5, startAngle: Angle(radians: end), endAngle: Angle(radians: start), clockwise: true)
            path.closeSubpath()
            context.fill(path, with: .color(colors[i % colors.count].opacity(breathe * 0.85)))
            start = end
        }
        // Track circles.
        for ring in [0.86, 0.68, 0.56] as [CGFloat] {
            var track = Path()
            track.addArc(center: center, radius: radius * ring, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(.white.opacity(0.4)), lineWidth: 0.6)
        }
    }

    private func drawBeam(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double) {
        // Wedge beam + leading edge line.
        let spread = 0.5
        var wedge = Path()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: radius, startAngle: Angle(radians: angle - spread), endAngle: Angle(radians: angle), clockwise: false)
        wedge.closeSubpath()
        let tip = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
        context.fill(
            wedge,
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.22, green: 0.63, blue: 0.97).opacity(0.5), .clear]),
                center: center, startRadius: 0, endRadius: radius))
        var edge = Path()
        edge.move(to: center)
        edge.addLine(to: tip)
        context.stroke(edge, with: .color(.white.opacity(0.9)), lineWidth: 1.2)
        context.fill(
            Path(ellipseIn: CGRect(x: tip.x - 2, y: tip.y - 2, width: 4, height: 4)),
            with: .color(.white))
    }

    private func drawHub(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        let pulse = 0.75 + 0.25 * sin(time * 2 * .pi / 2.0)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.9)))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius * 0.35, y: center.y - radius * 0.35, width: radius * 0.7, height: radius * 0.7)),
            with: .color(Color(red: 0.22, green: 0.63, blue: 0.97).opacity(pulse)))
    }

    private func drawPulse(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, time: Double) {
        // Expanding discovery ring.
        let cycle = (time.truncatingRemainder(dividingBy: 2.8)) / 2.8
        let r = radius * (1 + cycle * 0.25)
        var ring = Path()
        ring.addArc(center: center, radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        context.stroke(ring, with: .color(Color(red: 0.22, green: 0.63, blue: 0.97).opacity(0.35 * (1 - cycle))), lineWidth: 1)
    }
}

#Preview {
    VStack {
        ScanAnimationView(size: 150)
        ScanAnimationView(size: 64)
    }
    .padding()
}
