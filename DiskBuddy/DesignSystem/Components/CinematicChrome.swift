import SwiftUI

struct CinematicBrand: View {
    let compact: Bool
    let iconOnly: Bool
    var body: some View {
        HStack(spacing: compact ? 9 : 13) {
            ZStack {
                Circle().fill(RadialGradient(stops: [
                    .init(color: Color(hex: 0x131A23), location: 0.32), .init(color: Color(hex: 0x050A0E), location: 0.37),
                    .init(color: Color(hex: 0x2A3640), location: 0.44), .init(color: Color(hex: 0x060809), location: 0.54),
                    .init(color: Color(hex: 0x5B6771), location: 0.57), .init(color: Color(hex: 0x080A0C), location: 0.62)
                ], center: .center, startRadius: 0, endRadius: compact ? 20 : 24.5))
                Circle().strokeBorder(Color(hex: 0x7B8A95, opacity: 0.63), lineWidth: 1)
                Capsule().fill(Color(hex: 0xFF752A)).frame(width: 25, height: 2).rotationEffect(.degrees(-40))
                    .shadow(color: DesignTokens.Palette.orange, radius: 4)
            }
            .frame(width: compact ? 40 : 49, height: compact ? 40 : 49)
            .shadow(color: .black.opacity(0.6), radius: 7, y: 5)
            if !iconOnly {
                VStack(alignment: .leading, spacing: 5) {
                    (Text("DISK").foregroundColor(DesignTokens.Palette.text) + Text("DOOM").foregroundColor(Color(hex: 0xFF6828)))
                        .font(.system(size: compact ? 20 : 23, weight: .heavy)).tracking(0.15).fixedSize()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · LOCAL")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color(hex: 0x8896A2))
                }
            }
        }.frame(maxWidth: .infinity, alignment: iconOnly ? .center : .leading)
            .padding(.horizontal, iconOnly ? 0 : 4)
            .accessibilityElement(children: .ignore).accessibilityLabel("DiskDoom")
    }
}

struct CinematicRegionBackground: View {
    enum Region { case sidebar, workspace }
    let region: Region
    @AppStorage("industrialEffects") private var effects = true
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let (start, end) = CinematicCSS.endpoints(degrees: region == .sidebar ? 110 : 150, in: bounds)
            let stops: [Gradient.Stop] = region == .sidebar ? [
                .init(color: Color(hex: 0x0B1015, opacity: 0.96), location: 0),
                .init(color: Color(hex: 0x13191E, opacity: 0.96), location: 0.91),
                .init(color: Color(hex: 0x15222E, opacity: 0.6), location: 1)
            ] : [.init(color: Color(hex: 0x151C23), location: 0), .init(color: Color(hex: 0x0D1015), location: 0.22), .init(color: Color(hex: 0x0B0E13), location: 0.95)]
            context.fill(Path(bounds), with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end))
            if region == .sidebar && effects {
                context.fill(Path(bounds), with: .radialGradient(Gradient(colors: [Color(hex: 0xFD7420, opacity: 0.1), .clear]), center: CGPoint(x: size.width * 0.06, y: size.height * 0.85), startRadius: 0, endRadius: size.height * 0.35))
            }
            if region == .workspace {
                let edge = CGRect(x: 0, y: 0, width: 18, height: size.height)
                context.fill(Path(edge), with: .linearGradient(Gradient(colors: [.black.opacity(0.56), .clear]), startPoint: .zero, endPoint: CGPoint(x: 18, y: 0)))
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 1)), with: .color(Color(hex: 0x627A8B, opacity: 0.56)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Six bolts and three LED strips are mounted at the source CSS junctions.
/// This is a single static drawing, not a collection of animated view layers.
struct CinematicMountingDetails: View {
    let compact: Bool
    @AppStorage("industrialEffects") private var effects = true
    var body: some View {
        Canvas { context, size in
            let positions: [CGPoint] = [
                CGPoint(x: (compact ? 199 : 239) + 10.5, y: 120.5),
                CGPoint(x: (compact ? 204 : 258) + 10.5, y: size.height - 144.5),
                CGPoint(x: size.width - (compact ? 332 : 423) - 10.5, y: 99.5),
                CGPoint(x: size.width - (compact ? 323 : 412) - 10.5, y: 142.5),
                CGPoint(x: size.width - 18.5, y: 132.5),
                CGPoint(x: 276.5, y: size.height - 122.5)
            ]
            for center in positions {
                let circle = Path(ellipseIn: CGRect(x: center.x - 10.5, y: center.y - 10.5, width: 21, height: 21))
                var local = context
                local.clip(to: circle)
                local.fill(circle, with: .radialGradient(Gradient(stops: [
                    .init(color: Color(hex: 0xFAFAF5), location: 0), .init(color: Color(hex: 0xFAFAF5), location: 0.23),
                    .init(color: Color(hex: 0x181D22), location: 0.27), .init(color: Color(hex: 0x181D22), location: 0.42),
                    .init(color: Color(hex: 0x838E99), location: 0.45), .init(color: Color(hex: 0x838E99), location: 0.54),
                    .init(color: Color(hex: 0x090C0F), location: 0.56)
                ]), center: CGPoint(x: center.x - 4, y: center.y - 4), startRadius: 0, endRadius: 15))
                var slot = Path()
                slot.move(to: CGPoint(x: center.x - 4.3, y: center.y + 4.8))
                slot.addLine(to: CGPoint(x: center.x + 4.3, y: center.y - 4.8))
                local.stroke(slot, with: .color(Color(hex: 0x0A0D10)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if effects {
                for origin in [CGPoint(x: size.width * 0.37, y: 94), CGPoint(x: size.width * 0.17, y: size.height - 98), CGPoint(x: size.width * 0.94 - 96, y: size.height - 94)] {
                    context.fill(Path(CGRect(origin: origin, size: CGSize(width: 96, height: 3))), with: .linearGradient(Gradient(colors: [.clear, Color(hex: 0xFFB65B), Color(hex: 0xFF7325), .clear]), startPoint: origin, endPoint: CGPoint(x: origin.x + 96, y: origin.y)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
