import SwiftUI

// MARK: - §29 License Activation (server-backed) + §30 Success

struct LicenseView: View {
    @EnvironmentObject var store: LicenseStore
    @EnvironmentObject var overlays: OverlayStack
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var email = ""
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            ModalHeader(title: "License", overlayID: "license") {
                dismiss()
            }
            Image(systemName: store.isLicensed ? "checkmark.seal.fill" : "lock.open.fill")
                .font(.system(size: 64))
                .foregroundStyle(store.isLicensed ? .green : Color.accentColor)
            if store.isLicensed {
                // §30 success.
                Text("DiskDoom is Activated!")
                    .font(.title2.weight(.semibold))
                Text("All features are unlocked. License ID and device token are stored in the macOS Keychain — nothing sensitive touches disk or the repo.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                if store.serverReachable == false {
                    Text("Server unreachable — running on offline grace.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Start Using") { dismiss() }
                    .accentCTA()
                    .keyboardShortcut(.defaultAction)
                Button(store.isWorking ? "Working…" : "Deactivate This Mac") {
                    Task { await store.deactivateOnline() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .foregroundStyle(.red)
                .disabled(store.isWorking)
            } else {
                // §29 activation.
                Text("Activate DiskDoom")
                    .font(.title2.weight(.semibold))
                Text("Enter your license key and purchase email.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                TextField("License key (e.g. DB-XXXXXXXX)", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 320)
                    .autocorrectionDisabled()
                TextField("Purchase email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .frame(width: 320)
                    .autocorrectionDisabled()
                    .onSubmit { activate() }
                if let message = store.lastServerMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(store.serverReachable ? .red : .orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                Button(store.isWorking ? "Contacting server…" : "Activate") {
                    activate()
                }
                .accentCTA()
                .keyboardShortcut(.defaultAction)
                .disabled(store.isWorking)
                if store.trialDaysLeft > 0 {
                    Text("Trial: \(store.trialDaysLeft) days remaining (full features)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Trial expired — activate or use offline grace for read-only browsing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    TextField("Custom server URL (empty = api.diskbuddy.com)", text: $store.serverOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .frame(width: 360)
                        .autocorrectionDisabled()
                    Text("For local testing: run `wrangler dev` in the server folder, then enter http://localhost:8787/v1")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .frame(width: 360)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 480, height: 680)
        .onAppear {
            store.refresh()
            overlays.present("license")
        }
        .onDisappear { overlays.dismiss("license") }
    }

    private func activate() {
        Task {
            if await store.activateOnline(licenseID: key, email: email) {
                key = ""
                email = ""
            }
        }
    }
}

#Preview {
    LicenseView().environmentObject(LicenseStore())
}
