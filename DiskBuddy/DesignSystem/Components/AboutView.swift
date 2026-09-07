import SwiftUI

// MARK: - About DiskDoom window

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            DiskDoomLogo(style: .iconOnly, size: 120)
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text("DISK")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.white)
                    Text("DOOM")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(DiskDoomLogo.doomRed)
                }
                Text("Version \(appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Divider()
                .frame(width: 200)
            Text("Reclaim your storage.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("See what's eating your disk. Visualize it. Kill it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider()
                .frame(width: 200)
            VStack(spacing: 8) {
                Link("Website", destination: URL(string: "https://diskdoom.app")!)
                Link("Support", destination: URL(string: "mailto:support@diskdoom.app")!)
                Link("License Agreement", destination: URL(string: "https://diskdoom.app/eula")!)
            }
            .font(.callout)
            Text("Copyright 2024–2026. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(width: 360)
        .background(Color(red: 0.06, green: 0.06, blue: 0.1))
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
