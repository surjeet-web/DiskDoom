import SwiftUI

// MARK: - §01 Onboarding: Welcome

struct WelcomeView: View {
    @EnvironmentObject var state: AppState
    @State private var appeared = false

    var body: some View {
        VStack(spacing: DesignTokens.Space.l) {
            WizardHeader(step: 1, totalSteps: 3, onBack: nil) {
                state.refreshLimitedMode()
                state.finishOnboarding()
            }
            Spacer()
            DiskDoomLogo(style: .full, size: 120)
                .opacity(appeared ? 1 : 0)
            Text("Welcome to DiskDoom")
                .font(.largeTitle.weight(.semibold))
                .offset(y: appeared ? 0 : 12)
                .opacity(appeared ? 1 : 0)
            Text("Your Mac's storage is a mess. DiskDoom finds out exactly what's eating your disk — and gives you the tools to reclaim it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .opacity(appeared ? 1 : 0)
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Label("Fast — 2M files in ~10s", systemImage: "bolt.fill")
                Label("On-device — nothing leaves your Mac", systemImage: "lock.fill")
                Label("Smart — duplicates, stale caches, hidden leftovers", systemImage: "sparkles")
            }
            .font(.callout)
            .specCard()
            .opacity(appeared ? 1 : 0)
            Spacer()
            Button("Get Started") {
                withAnimation(.easeOut(duration: DesignTokens.Motion.base)) {
                    state.onboardingStep = .fullDiskAccess
                }
            }
            .accentCTA()
            .keyboardShortcut(.defaultAction)
            Button("Already have a license? Activate") {
                state.showLicense = true
            }
            .buttonStyle(.link)
            .font(.caption)
            .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: DesignTokens.Layout.onboardingWidth, height: 620)
        .onAppear {
            let motionOK = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(.easeOut(duration: motionOK ? DesignTokens.Motion.slow : 0)) {
                appeared = true
            }
        }
    }
}

#Preview {
    WelcomeView().environmentObject(AppState())
}
