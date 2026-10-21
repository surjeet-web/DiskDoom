import SwiftUI

// MARK: - Root: onboarding (§01–§03) vs main window (§04–§06)

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("listRowHeight") private var rowHeight = 40.0

    private var accent: Color? {
        switch state.accentName {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "red": return .red
        default: return DesignTokens.Palette.orange
        }
    }

    var body: some View {
        Group {
            if let step = state.onboardingStep {
                Group {
                    switch step {
                    case .welcome: WelcomeView()
                    case .fullDiskAccess: FullDiskAccessView()
                    case .scanTarget: ScanTargetView()
                    }
                }
                .industrialPanel(.tiered, flatSide: .bottom, accent: DesignTokens.Palette.orange)
                .id(step)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
            } else {
                MainWindowView()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(reduceMotion ? nil : DesignTokens.Motion.navigation, value: state.onboardingStep)
        .sheet(isPresented: $state.showLicense) {
            LicenseView().environmentObject(state.license)
        }
        .tint(accent)
        .environment(\.defaultMinListRowHeight, CGFloat(rowHeight))
        .preferredColorScheme(.dark)
        .background(DesignTokens.Palette.void)
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
