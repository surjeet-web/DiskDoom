import SwiftUI

// MARK: - Root: onboarding (§01–§03) vs main window (§04–§06)

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private var accent: Color? {
        switch state.accentName {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "red": return .red
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let step = state.onboardingStep {
                switch step {
                case .welcome: WelcomeView()
                case .fullDiskAccess: FullDiskAccessView()
                case .scanTarget: ScanTargetView()
                }
            } else {
                MainWindowView()
            }
        }
        .tint(accent)
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
