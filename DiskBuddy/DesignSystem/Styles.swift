import SwiftUI

// MARK: - Shared styles (prototype)

// Accent CTA button per spec §01/§02/§03 (320pt wide, title3 weight).
struct AccentCTAButton: ViewModifier {
    var enabled: Bool = true

    func body(content: Content) -> some View {
        content
            .font(.title3.weight(.semibold))
            .frame(width: 320)
            .padding(.vertical, DesignTokens.Space.s)
            .background(enabled ? Color.accentColor : Color.secondary.opacity(0.3))
            .foregroundStyle(enabled ? .white : .secondary)
            .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
            .opacity(enabled ? 1 : 0.6)
    }
}

extension View {
    func accentCTA(enabled: Bool = true) -> some View {
        modifier(AccentCTAButton(enabled: enabled))
    }

    /// Subtle spec card: quaternary fill, 10pt radius (§01 feature cards, §02 info card).
    func specCard() -> some View {
        padding(DesignTokens.Space.m)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
    }
}
