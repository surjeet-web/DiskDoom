import SwiftUI
import AppKit

// MARK: - §17 Uninstall Confirmation Sheet (real bundle + artifacts, always Trash)

struct UninstallSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var overlays: OverlayStack
    @EnvironmentObject var inventory: AppInventoryService
    let app: AppEntry
    @State private var excludedPaths: Set<String> = []

    private var sharedArtifacts: [AppArtifactInfo] {
        app.artifacts.filter { artifact in
            inventory.sharedArtifactOwners.contains(where: {
                artifact.path.localizedCaseInsensitiveContains($0)
            })
        }
    }

    private var stagedTotal: Int64 {
        let bundle = app.isStale || excludedPaths.contains(app.bundlePath) ? 0 : app.bundleBytes
        let artifacts = app.artifacts
            .filter { !excludedPaths.contains($0.path) }
            .reduce(0) { $0 + $1.bytes }
        return bundle + artifacts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.m) {
            ModalHeader(title: app.isStale ? "Remove Leftovers" : "Uninstall", overlayID: "uninstall") {
                state.uninstallApp = nil
            }
            HStack(spacing: DesignTokens.Space.m) {
                if !app.bundlePath.isEmpty {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath))
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading) {
                    Text("\(app.isStale ? "Remove leftovers of" : "Uninstall") \(app.name)?")
                        .font(.title2.weight(.semibold))
                    Text("\(app.bundleID) · v\(app.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("This will move the following to the Trash (uncheck to keep):")
                .font(.callout)
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                    if !app.isStale && !app.bundlePath.isEmpty {
                        Toggle(isOn: Binding(
                            get: { !excludedPaths.contains(app.bundlePath) },
                            set: { keep in
                                if keep { excludedPaths.remove(app.bundlePath) }
                                else { excludedPaths.insert(app.bundlePath) }
                            })) {
                            HStack {
                                Text("Application bundle").font(.caption.weight(.semibold))
                                Spacer()
                                Text(app.bundleBytes.fileSizeString).font(.caption.monospacedDigit())
                            }
                        }
                        Text(app.bundlePath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Divider()
                    }
                    Text("Artifacts (\(app.artifacts.count))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if app.artifacts.isEmpty {
                        Text("No leftover files found — clean install record.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(app.artifacts, id: \.path) { artifact in
                        Toggle(isOn: Binding(
                            get: { !excludedPaths.contains(artifact.path) },
                            set: { keep in
                                if keep { excludedPaths.remove(artifact.path) }
                                else { excludedPaths.insert(artifact.path) }
                            })) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(shortPath(artifact.path))
                                        .font(.callout.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(artifact.kind)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(artifact.bytes.fileSizeString)
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .specCard()
            if !sharedArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                    Label(
                        "\(sharedArtifacts.count) shared resource(s) are also used by other apps. Uncheck them above to keep them.",
                        systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    ForEach(sharedArtifacts.prefix(3), id: \.path) { artifact in
                        Text(shortPath(artifact.path))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(DesignTokens.Space.m)
                .background(.orange.opacity(0.08))
                .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
            }
            Text("Estimated total to move to Trash: \(stagedTotal.fileSizeString)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
            HStack {
                Spacer()
                Button("Cancel") { state.uninstallApp = nil }
                    .buttonStyle(.bordered)
                Button("Move to Trash") {
                    if !app.isStale, !app.bundlePath.isEmpty, !excludedPaths.contains(app.bundlePath) {
                        state.stage(source: "Uninstall", path: app.bundlePath, bytes: app.bundleBytes)
                    }
                    for artifact in app.artifacts where !excludedPaths.contains(artifact.path) {
                        state.stage(source: "Uninstall", path: artifact.path, bytes: artifact.bytes)
                    }
                    state.uninstallApp = nil
                    state.showCleanup = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(stagedTotal == 0)
            }
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 560, height: 620)
        .onAppear { overlays.present("uninstall") }
        .onDisappear { overlays.dismiss("uninstall") }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

#Preview {
    UninstallSheet(app: AppEntry(
        name: "PreviewApp", bundleID: "com.preview.app", bundlePath: "/Applications/PreviewApp.app",
        version: "1.0", bundleBytes: 1_000_000_000, artifacts: [],
        installDate: Date(), isStale: false))
        .environmentObject(AppState())
        .environmentObject(AppInventoryService())
}
