import SwiftUI

// MARK: - §29 License Activation + §30 License Success (prototype, Keychain/server stubbed)

struct LicenseView: View {
    @EnvironmentObject var state: AppState
    @State private var key = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: state.licenseActive ? "checkmark.seal.fill" : "lock.open.fill")
                .font(.system(size: 64))
                .foregroundStyle(state.licenseActive ? .green : Color.accentColor)
            if state.licenseActive {
                // §30 success.
                Text("DiskBuddy is Activated!")
                    .font(.title2.weight(.semibold))
                Text("Thank you for purchasing DiskBuddy. All features are now unlocked permanently.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Start Using") { state.showLicense = false }
                    .accentCTA()
                    .keyboardShortcut(.defaultAction)
            } else {
                // §29 activation.
                Text("Activate DiskBuddy")
                    .font(.title2.weight(.semibold))
                Text("Enter your license key to unlock all features.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 320)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Activate") {
                    let valid = key.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
                    if valid {
                        state.licenseActive = true
                    } else {
                        error = "That key looks too short — check for typos and try again."
                    }
                }
                .accentCTA()
                .keyboardShortcut(.defaultAction)
                Button("Purchase License") { }
                    .buttonStyle(.bordered)
                Text("Trial: 14 days remaining (full features)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Enter Offline Mode") { state.showLicense = false }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 480, height: 560)
    }
}

#Preview {
    LicenseView().environmentObject(AppState())
}
