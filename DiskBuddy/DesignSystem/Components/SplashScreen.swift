import SwiftUI

// MARK: - Launch splash (auto-dismisses; static when Reduce Motion is on)

struct SplashScreen: View {
    let onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity = 0.0
    @State private var textOpacity = 0.0
    @State private var glowOpacity = 0.0

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07)
                .ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.2, blue: 0.0).opacity(glowOpacity * 0.1),
                    Color.clear,
                ],
                center: .center, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()
            VStack(spacing: 32) {
                DiskDoomLogo(style: .iconOnly, size: 180)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("DISK")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(.white)
                        Text("DOOM")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(DiskDoomLogo.doomRed)
                    }
                    Text("Reclaim your storage.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .opacity(textOpacity)
            }
        }
        .onAppear {
            if reduceMotion {
                logoScale = 1.0
                logoOpacity = 1.0
                textOpacity = 1.0
                glowOpacity = 0.5
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                    logoScale = 1.0
                    logoOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    textOpacity = 1.0
                }
                withAnimation(.easeInOut(duration: 1.5)) {
                    glowOpacity = 1.0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.6 : 2.0)) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    onComplete()
                }
            }
        }
    }
}
