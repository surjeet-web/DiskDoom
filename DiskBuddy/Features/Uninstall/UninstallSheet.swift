import SwiftUI

// MARK: - §17 Applications: Uninstall Confirmation Sheet (always Trash, never delete)

struct UninstallSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var overlays: OverlayStack
    let app: AppEntry
    @State private var keepSharedFramework = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            ModalHeader(title: "Uninstall", overlayID: "uninstall") {
                state.uninstallApp = nil
            }
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: app.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(app.tint)
                Text("Uninstall \(app.name)?")
                    .font(.title2.weight(.semibold))
            }
            Text("This will move the following to the Trash:")
                .font(.callout)
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Text("Application").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("/Applications/\(app.name).app — \(app.bundleBytes.fileSizeString)")
                    .font(.callout.monospaced())
            }
            .specCard()
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Text("Artifacts (\(8) files)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Group {
                    Text("~/Library/Caches/\(app.bundleID) — 5.2 GB")
                    Text("~/Library/HTTPStorages/\(app.bundleID) — 2.1 GB")
                    Text("~/Library/Application Support/\(app.name)/ — 0.6 GB")
                    Text("~/Library/Preferences/\(app.bundleID).plist — 12 KB")
                }
                .font(.callout.monospaced())
            }
            .specCard()
            if app.name == "Google Chrome" {
                VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                    Label("GoogleSoftwareUpdate.framework is also used by: Google Drive, Google Earth. Removing may affect these apps.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Toggle("Keep this framework", isOn: $keepSharedFramework)
                        .font(.caption)
                }
                .padding(DesignTokens.Space.m)
                .background(.orange.opacity(0.08))
                .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
            }
            Text("Total to free: \(app.totalBytes.fileSizeString)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
            HStack {
                Spacer()
                Button("Cancel") { state.uninstallApp = nil }
                    .buttonStyle(.bordered)
                Button("Move to Trash") {
                    state.stage(source: "Uninstall", path: "/Applications/\(app.name).app", bytes: app.bundleBytes)
                    state.stage(source: "Uninstall", path: "\(app.name) artifacts", bytes: app.artifactBytes)
                    state.uninstallApp = nil
                    state.showCleanup = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 520)
        .onAppear { overlays.present("uninstall") }
        .onDisappear { overlays.dismiss("uninstall") }
    }
}

#Preview {
    UninstallSheet(app: MockApps.all[0]).environmentObject(AppState())
}
