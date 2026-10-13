import SwiftUI

// MARK: - Launch splash (auto-dismisses; static when Reduce Motion is on)

struct SplashScreen: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var logoScale: CGFloat = 0.86
    @State private var logoOpacity = 0.0
    @State private var textOpacity = 0.0
    @State private var glowOpacity = 0.0
    @State private var completed = false

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
                    .shadow(color: DiskDoomLogo.doomRed.opacity(glowOpacity * 0.22), radius: 42)
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
            VStack {
                HStack {
                    Spacer()
                    Button("Skip intro") { complete() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(20)
                        .accessibilityLabel("Skip intro")
                }
                Spacer()
            }
        }
        .onAppear {
            if reduceMotion {
                logoScale = 1.0
                logoOpacity = 1.0
                textOpacity = 1.0
                glowOpacity = 0.5
            } else {
                withAnimation(DesignTokens.Motion.navigation) {
                    logoScale = 1.0
                    logoOpacity = 1.0
                }
                withAnimation(DesignTokens.Motion.entrance.delay(0.16)) {
                    textOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.9)) {
                    glowOpacity = 1.0
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.35 : 1.35))
            guard !Task.isCancelled else { return }
            complete()
        }
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.slow)) {
            onComplete()
        }
    }
}
