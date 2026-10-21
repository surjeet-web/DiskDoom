import SwiftUI

// MARK: - Shared native industrial styles

// Accent CTA button per spec §01/§02/§03 (320pt wide, title3 weight).
struct AccentCTAButton: ViewModifier {
    var enabled: Bool = true

    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.semibold))
            .frame(maxWidth: 320)
            .padding(.vertical, DesignTokens.Space.s)
            .background(enabled ? DesignTokens.Palette.orange : Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(enabled ? Color.black : Color.secondary)
            .opacity(enabled ? 1 : 0.6)
    }
}

extension View {
    func accentCTA(enabled: Bool = true) -> some View {
        modifier(AccentCTAButton(enabled: enabled))
    }

    /// Legacy call sites share the same protected industrial panel contract.
    func specCard() -> some View {
        industrialPanel(.plate)
    }
}
