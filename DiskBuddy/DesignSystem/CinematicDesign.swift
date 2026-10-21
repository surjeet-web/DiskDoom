import SwiftUI

// Direct translations of diskdoom-cinematic (1).html. CSS pixels map to
// logical points; percentages, stops and breakpoints are kept explicit.
enum CinematicCSS {
    static let shell: [CGPoint] = points([(0.015, 0), (0.388, 0), (0.413, 0.03), (0.652, 0.03), (0.666, 0), (0.975, 0), (1, 0.04), (1, 0.94), (0.96, 1), (0.03, 1), (0, 0.96), (0, 0.04)])
    static let scan: [CGPoint] = points([(0.05, 0), (0.95, 0), (1, 0.34), (1, 0.64), (0.94, 0.96), (0.05, 0.96), (0, 0.65), (0, 0.31)])
    static let headerRight: [CGPoint] = points([(0.08, 0), (0.96, 0), (1, 0.24), (1, 1), (0, 1), (0, 0.28)])
    static let footer: [CGPoint] = points([(0, 0), (0.13, 0), (0.15, 0.16), (0.30, 0.16), (0.32, 0), (0.59, 0), (0.61, 0.18), (0.73, 0.18), (0.75, 0), (1, 0), (1, 0.65), (0.96, 1), (0.03, 1), (0, 0.78)])

    private static func points(_ values: [(Double, Double)]) -> [CGPoint] {
        values.map { CGPoint(x: $0.0, y: $0.1) }
    }

    static func path(_ points: [CGPoint], in rect: CGRect) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }

    /// CSS 0° points upward; SwiftUI's unit-point diagonal is not equivalent
    /// on a nonsquare panel. Keep the CSS gradient line's aspect ratio.
    static func endpoints(degrees: Double, in rect: CGRect) -> (CGPoint, CGPoint) {
        let angle = degrees * .pi / 180
        let dx = sin(angle), dy = -cos(angle)
        let length = abs(rect.width * dx) + abs(rect.height * dy)
        return (CGPoint(x: rect.midX - dx * length / 2, y: rect.midY - dy * length / 2),
                CGPoint(x: rect.midX + dx * length / 2, y: rect.midY + dy * length / 2))
    }

    static func fill(_ context: inout GraphicsContext, path: Path, rect: CGRect,
                     degrees: Double, stops: [(UInt32, Double)]) {
        let (start, end) = endpoints(degrees: degrees, in: rect)
        context.fill(path, with: .linearGradient(Gradient(stops: stops.map {
            .init(color: Color(hex: $0.0), location: $0.1)
        }), startPoint: start, endPoint: end))
    }
}

struct CinematicMetrics: Equatable {
    let viewport: CGSize
    let expanded: Bool
    let inspector: Bool
    var compact: Bool { viewport.width <= 1330 }
    var stacked: Bool { viewport.width <= 1030 }
    var margin: CGFloat { compact ? 8 : 23 }
    var sidebar: CGFloat { !expanded ? 68 : stacked ? 195 : compact ? 206 : 252 }
    var inspectorWidth: CGFloat { inspector && !stacked ? (compact ? 330 : 416) : 0 }
    var searchWidth: CGFloat { compact ? 330 : 416 }
    var headerHeight: CGFloat { stacked ? 75 : compact ? 78 : 90 }
    // The CSS footer has min-height:91px, including at its 76px grid track.
    // Reserve that actual visible height instead of reproducing its overflow.
    var footerHeight: CGFloat { stacked ? 80 : compact ? 91 : 94 }
    var stackedInspectorHeight: CGFloat { inspector && stacked ? 410 : 0 }
    // Browser-measured intrinsic middle row (20 source navigation entries).
    // A minmax(670,1fr) track actually resolves to 985px, not 670px.
    var minimumBody: CGFloat { stacked ? 600 : compact ? 916 : 985 }
    var width: CGFloat { min(1630, max(0, viewport.width - margin * 2)) }
    var bodyHeight: CGFloat {
        let minimum = max(minimumBody, (compact ? 820 : 880) - headerHeight - footerHeight - stackedInspectorHeight)
        return max(minimum, viewport.height - margin * 2 - headerHeight - footerHeight - stackedInspectorHeight)
    }
    var shellHeight: CGFloat { headerHeight + bodyHeight + stackedInspectorHeight + footerHeight }
}

struct CinematicStage: View {
    @AppStorage("industrialEffects") private var effects = true
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Color(hex: 0x080B0E), location: 0), .init(color: Color(hex: 0x1B2730), location: 0.72), .init(color: Color(hex: 0x0B1016), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if effects {
                RadialGradient(colors: [Color(hex: 0xEC5F14).opacity(0.3), .clear], center: UnitPoint(x: 0.96, y: 0.87), startRadius: 0, endRadius: 340)
                RadialGradient(colors: [Color(hex: 0x4A6F86).opacity(0.3), .clear], center: UnitPoint(x: 0.75, y: 0.1), startRadius: 0, endRadius: 580)
                RadialGradient(colors: [Color(hex: 0xFF6B1D).opacity(0.18), .clear], center: UnitPoint(x: 0.02, y: 0.92), startRadius: 0, endRadius: 280)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CinematicShellBacking: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            CinematicCSS.fill(&context, path: CinematicCSS.path(CinematicCSS.shell, in: bounds), rect: bounds, degrees: 128,
                              stops: [(0x9CA9B3, 0), (0x3B4751, 0.13), (0x19232B, 0.36), (0x93A8B8, 0.71), (0x39444D, 0.92)])
            let inner = bounds.insetBy(dx: 2, dy: 2)
            let path = CinematicCSS.path(CinematicCSS.shell, in: inner)
            CinematicCSS.fill(&context, path: path, rect: inner, degrees: 160, stops: [(0x11191F, 0), (0x090B0D, 1)])
            var face = context
            face.clip(to: path)
            face.fill(path, with: .radialGradient(Gradient(stops: [.init(color: Color(hex: 0x283743), location: 0), .init(color: Color(hex: 0x0B0D10), location: 0.38), .init(color: Color(hex: 0x080C10), location: 0.75)]), center: CGPoint(x: size.width * 0.85, y: size.height * 0.1), startRadius: 0, endRadius: size.width * 0.75))
        }
        .shadow(color: .black.opacity(0.67), radius: 24, x: 0, y: 20)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CinematicScanBacking: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            CinematicCSS.fill(&context, path: CinematicCSS.path(CinematicCSS.scan, in: bounds), rect: bounds, degrees: 180,
                              stops: [(0x7A8C99, 0), (0x182029, 0.45), (0xC17B4A, 0.95)])
            let inset = bounds.insetBy(dx: 2, dy: 2)
            CinematicCSS.fill(&context, path: CinematicCSS.path(CinematicCSS.scan, in: inset), rect: inset, degrees: 140,
                              stops: [(0x12171D, 0), (0x090C10, 1)])
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CinematicHeaderBacking: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            CinematicCSS.fill(&context, path: CinematicCSS.path(CinematicCSS.headerRight, in: bounds), rect: bounds, degrees: 165,
                              stops: [(0x374E60, 0), (0x1A242D, 0.5), (0x10151A, 1)])
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CinematicFooterBacking: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            CinematicCSS.fill(&context, path: CinematicCSS.path(CinematicCSS.footer, in: bounds), rect: bounds, degrees: 160,
                              stops: [(0x708DA2, 0), (0x25313B, 0.18), (0x11171D, 0.36), (0x617583, 0.75), (0xE87931, 1)])
            let inset = bounds.insetBy(dx: 3, dy: 3)
            CinematicCSS.fill(&context, path: CinematicCSS.path(CinematicCSS.footer, in: inset), rect: inset, degrees: 180,
                              stops: [(0x0B1116, 0), (0x15191E, 1)])
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CinematicIconButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Color(hex: 0xD5E2ED))
            .frame(width: 38, height: 38)
            .background(LinearGradient(colors: [Color(hex: 0x34424F), Color(hex: 0x151B21)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color(hex: 0x22C8FC) : Color(hex: 0x627384, opacity: 0.53), lineWidth: 1) }
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

struct CinematicModeButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(selected ? Color(hex: 0x0B0F14) : DesignTokens.Palette.text)
            .padding(.horizontal, 12).frame(height: 39)
            .background {
                Capsule().fill(LinearGradient(stops: selected ? [.init(color: Color(hex: 0xFFBB48), location: 0), .init(color: Color(hex: 0xFF711E), location: 0.47), .init(color: Color(hex: 0xF75C12), location: 1)] : [.init(color: Color(hex: 0x20272E), location: 0), .init(color: Color(hex: 0x101419), location: 1)], startPoint: .top, endPoint: .bottom))
            }
            .overlay { Capsule().strokeBorder(selected ? Color(hex: 0xFFA744) : Color(hex: 0x404B53, opacity: 0.49), lineWidth: 1) }
            .shadow(color: selected ? Color(hex: 0xFF721B, opacity: 0.35) : .black.opacity(0.38), radius: selected ? 7 : 3, y: 3)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct CinematicNavigationStyle: ButtonStyle {
    var selected: Bool
    var compact: Bool
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: compact ? 32 : 34)
            .padding(.horizontal, compact ? 7 : 9)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7).fill(LinearGradient(stops: [.init(color: Color(hex: 0x8D361D), location: 0), .init(color: Color(hex: 0xFB662C), location: 0.09), .init(color: Color(hex: 0xA74422), location: 0.49), .init(color: Color(hex: 0x166BE7), location: 1)], startPoint: .leading, endPoint: .trailing))
                } else { RoundedRectangle(cornerRadius: 7).fill(hovered ? Color(hex: 0x254057, opacity: 0.48) : .clear) }
            }
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color(hex: 0x589BF9) : hovered ? Color(hex: 0x557388, opacity: 0.48) : .clear, lineWidth: 1) }
            .shadow(color: selected ? Color(hex: 0x168AFF, opacity: 0.25) : .clear, radius: 6)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .onHover { hovered = $0 }
    }
}

struct CinematicTelemetry: View {
    var body: some View {
        Canvas { context, size in
            for group in 0..<4 {
                for i in 0..<27 {
                    let x = CGFloat(group) * (size.width / 4) + CGFloat(i % 14) * 5
                    let y = CGFloat(i / 14) * 11
                    let bar = CGRect(x: x, y: y, width: i % 11 == 0 ? 8 : 2, height: i % 4 == 0 ? 9 : 5)
                    context.fill(Path(bar), with: .color(Color(hex: 0xB1C4D0).opacity(0.6)))
                }
            }
        }.frame(height: 22).allowsHitTesting(false).accessibilityHidden(true)
    }
}
