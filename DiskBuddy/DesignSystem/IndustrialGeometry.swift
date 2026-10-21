import SwiftUI

// Decoration stays behind native controls, never masks their focus rings.
enum DockEdge: String, CaseIterable { case top, right, bottom, left }
enum ChassisFamily: String, CaseIterable { case plate, canopy, tiered, well, boot }

struct ChassisShape: Shape {
    var family: ChassisFamily = .plate
    var flatSide: DockEdge = .right
    var cut: CGFloat = DesignTokens.Geometry.cut

    func vertices(in r: CGRect) -> [CGPoint] {
        guard r.width > 0, r.height > 0 else { return [] }
        let c = min(max(0, cut), r.width / 6, r.height / 4)
        let l = r.minX, t = r.minY, w = r.width, h = r.height
        let tl: CGFloat = flatSide == .top || flatSide == .left ? 0 : c
        let tr: CGFloat = flatSide == .top || flatSide == .right ? 0 : c
        let br: CGFloat = flatSide == .bottom || flatSide == .right ? 0 : c
        let bl: CGFloat = flatSide == .bottom || flatSide == .left ? 0 : c
        var p = [CGPoint(x: l + tl, y: t)]
        if (family == .tiered || family == .canopy), flatSide != .top, w > c * 8 {
            p += [CGPoint(x: l + w * 0.36, y: t), CGPoint(x: l + w * 0.36 + c / 2, y: t + c / 2),
                  CGPoint(x: l + w * 0.62, y: t + c / 2), CGPoint(x: l + w * 0.62 + c / 2, y: t)]
        }
        p += [CGPoint(x: l + w - tr, y: t), CGPoint(x: l + w, y: t + tr),
              CGPoint(x: l + w, y: t + h - br), CGPoint(x: l + w - br, y: t + h)]
        if family == .boot, flatSide != .bottom, w > c * 8 {
            p += [CGPoint(x: l + w * 0.42, y: t + h), CGPoint(x: l + w * 0.42 - c / 2, y: t + h - c / 2),
                  CGPoint(x: l + w * 0.2, y: t + h - c / 2), CGPoint(x: l + w * 0.2 - c / 2, y: t + h)]
        }
        p += [CGPoint(x: l + bl, y: t + h), CGPoint(x: l, y: t + h - bl), CGPoint(x: l, y: t + tl)]
        return p
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            let points = vertices(in: rect)
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
    }

    // Exactly zero depth on the docking edge, unlike an offset copy of a card.
    static func extrusion(for edge: DockEdge, flatSide: DockEdge, depth: CGFloat) -> CGSize {
        guard edge != flatSide else { return .zero }
        switch edge {
        case .top: return CGSize(width: 0, height: -depth)
        case .right: return CGSize(width: depth, height: 0)
        case .bottom: return CGSize(width: 0, height: depth)
        case .left: return CGSize(width: -depth, height: 0)
        }
    }
}

struct MetalSurface: View {
    var family: ChassisFamily = .plate
    var flatSide: DockEdge = .right
    var depth: CGFloat = DesignTokens.Geometry.depth
    var accent: Color = DesignTokens.Palette.cyan
    var active = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Compatibility for feature call sites: the reference uses inset
        // rounded reading panels, not an extruded polygon around every card.
        RoundedRectangle(cornerRadius: family == .canopy ? 16 : 9)
            .fill(LinearGradient(stops: [.init(color: Color(hex: 0x263441), location: 0),
                                        .init(color: Color(hex: 0x101820), location: 0.55),
                                        .init(color: Color(hex: 0x0A1016), location: 1)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: family == .canopy ? 16 : 9)
                    .strokeBorder(contrast == .increased ? .white : active ? accent : Color(hex: 0x394F5B), lineWidth: contrast == .increased ? 2 : 1)
            }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct IndustrialPanel: ViewModifier {
    var family: ChassisFamily = .plate
    var flatSide: DockEdge = .right
    var accent: Color = DesignTokens.Palette.cyan
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background { MetalSurface(family: family, flatSide: flatSide, accent: accent) }
            .padding(4)
    }
}

extension View {
    func industrialPanel(_ family: ChassisFamily = .plate, flatSide: DockEdge = .right,
                         accent: Color = DesignTokens.Palette.cyan) -> some View {
        modifier(IndustrialPanel(family: family, flatSide: flatSide, accent: accent))
    }
}

struct PlateButtonStyle: ButtonStyle {
    var selected = false
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(primary ? Color(hex: 0x091018) : DesignTokens.Palette.text)
            .background {
                if primary {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color(hex: 0xFFAE4A), Color(hex: 0xF16319)], startPoint: .top, endPoint: .bottom))
                } else {
                    MetalSurface(depth: 2, accent: DesignTokens.Palette.orange, active: selected)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(focused ? Color.white : selected ? DesignTokens.Palette.orange : Color.clear,
                            lineWidth: focused ? 2 : 1)
                    .padding(2)
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}
