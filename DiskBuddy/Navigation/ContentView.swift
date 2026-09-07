import SwiftUI

// MARK: - Root: onboarding (§01–§03) vs main window (§04–§06)

struct ContentView: View {
    @EnvironmentObject var state: AppState

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
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
