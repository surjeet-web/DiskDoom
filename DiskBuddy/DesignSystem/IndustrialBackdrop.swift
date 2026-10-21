import SwiftUI

struct IndustrialBackdrop: View {
    @AppStorage("industrialEffects") private var effects = true
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            DesignTokens.Palette.void
            if effects && contrast != .increased {
                GeometryReader { geometry in
                    RadialGradient(colors: [DesignTokens.Palette.orange.opacity(0.1), .clear], center: .bottomTrailing,
                                   startRadius: 0, endRadius: min(geometry.size.width, geometry.size.height) * 0.55)
                    RadialGradient(colors: [DesignTokens.Palette.cyan.opacity(0.04), .clear], center: .topLeading,
                                   startRadius: 0, endRadius: geometry.size.width * 0.35)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
