import SwiftUI

// MARK: - §29 License Activation (real trial countdown + Keychain) + §30 Success

struct LicenseView: View {
    @EnvironmentObject var store: LicenseStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: store.isLicensed ? "checkmark.seal.fill" : "lock.open.fill")
                .font(.system(size: 64))
                .foregroundStyle(store.isLicensed ? .green : Color.accentColor)
            if store.isLicensed {
                // §30 success.
                Text("DiskBuddy is Activated!")
                    .font(.title2.weight(.semibold))
                Text("Thank you for purchasing DiskBuddy. All features are now unlocked permanently. Your key is stored in the macOS Keychain.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Start Using") { dismiss() }
                    .accentCTA()
                    .keyboardShortcut(.defaultAction)
                Button("Deactivate") { store.deactivate() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(.red)
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
                    .onSubmit { activate() }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Activate") { activate() }
                    .accentCTA()
                    .keyboardShortcut(.defaultAction)
                Button("Purchase License") { }
                    .buttonStyle(.bordered)
                if store.trialDaysLeft > 0 {
                    Text("Trial: \(store.trialDaysLeft) days remaining (full features)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Trial expired — read-only mode until you activate.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let grace = store.graceDaysLeft {
                    Text("Offline grace: \(grace) days remaining.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 480, height: 600)
        .onAppear { store.refresh() }
    }

    private func activate() {
        if store.activate(key: key) {
            error = nil
        } else {
            error = "That key looks too short — check for typos and try again."
        }
    }
}

#Preview {
    LicenseView().environmentObject(LicenseStore())
}
