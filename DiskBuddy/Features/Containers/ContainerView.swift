import SwiftUI
import AppKit

// MARK: - D9 Container Isolation view

struct ContainerView: View {
    @EnvironmentObject var scanner: ContainerScanner
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Containers").font(.title2.weight(.semibold))
                    Text("\(scanner.containers.count) containers · \(ByteFormatting.format(scanner.totalBytes))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if scanner.isScanning {
                    Button("Cancel") { scanner.cancel() }.buttonStyle(.bordered)
                } else {
                    Button("Scan") { scanner.scan() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(DesignTokens.Space.m)
            Divider()
            if scanner.isScanning && scanner.containers.isEmpty {
                ProgressView("Scanning ~/Library/Containers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scanner.containers.isEmpty {
                EmptyState(symbol: "square.grid.3x3.fill.square", title: "No containers scanned", message: "Reveal what's inside each sandboxed app's private container.", actionTitle: "Scan Containers", action: { scanner.scan() })
            } else {
                List {
                    ForEach(scanner.containers) { container in
                        DisclosureGroup {
                            ForEach(Array(container.topItems.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: DesignTokens.Space.s) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(kindColor(item.kind))
                                        .frame(width: 14)
                                    Text(item.name).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text(ByteFormatting.format(item.bytes))
                                        .font(.caption.monospacedDigit())
                                }
                                .padding(.vertical, 1)
                            }
                            HStack {
                                Spacer()
                                Button("Stage Container for Cleanup") {
                                    state.stage(source: "Containers", path: "~/Library/Containers/\(container.bundleID)", bytes: container.totalBytes)
                                    state.showCleanup = true
                                }
                                .font(.caption).buttonStyle(.bordered).controlSize(.small)
                            }
                        } label: {
                            HStack(spacing: DesignTokens.Space.m) {
                                containerIcon(for: container)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(container.appName).font(.body.weight(.medium))
                                    Text(container.bundleID).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(ByteFormatting.format(container.totalBytes))
                                    .font(.callout.monospacedDigit())
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { if scanner.containers.isEmpty { scanner.scan() } }
        .onDisappear { scanner.cancel() }
    }

    private func containerIcon(for container: SandboxContainer) -> some View {
        Group {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: container.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "square.grid.3x3.fill.square")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }
        }
    }

    private func kindColor(_ kind: SandboxContainer.ItemKind) -> Color {
        switch kind {
        case .cache: return .orange
        case .preferences: return .purple
        case .savedState: return .blue
        case .tmp: return .gray
        case .data: return .teal
        case .other: return .secondary
        }
    }
}

#Preview {
    ContainerView()
        .environmentObject(ContainerScanner())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
