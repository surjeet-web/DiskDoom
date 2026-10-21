import SwiftUI
import AppKit

// MARK: - §03 Scan Target Selection (real volumes, real folder picker)

struct ScanTargetView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: ScanTarget = .fullMac
    @State private var customFolder: URL? = nil
    @State private var selectedExternalPath: String? = nil
    @State private var volumes: [(name: String, path: String, used: Int64, total: Int64)] = []

    enum ScanTarget: String, CaseIterable, Identifiable {
        case fullMac, home, folder, external
        var id: String { rawValue }

        var title: String {
            switch self {
            case .fullMac: return "Full Mac"
            case .home: return "Home Folder"
            case .folder: return "Choose Folder…"
            case .external: return "External Volume"
            }
        }

        var symbol: String {
            switch self {
            case .fullMac: return "desktopcomputer"
            case .home: return "house.fill"
            case .folder: return "folder.fill"
            case .external: return "externaldrive.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            WizardHeader(
                step: 3,
                totalSteps: 3,
                onBack: {
                    withAnimation(.easeOut(duration: DesignTokens.Motion.base)) {
                        state.onboardingStep = .fullDiskAccess
                    }
                }) {
                state.refreshLimitedMode()
                state.finishOnboarding()
            }
            Text("What do you want to scan?")
                .font(.title2.weight(.semibold))
                .padding(.top, DesignTokens.Space.xl)
            VStack(spacing: DesignTokens.Space.s) {
                targetRow(.fullMac, subtitle: "Everything — system, apps, user folders, caches. \(volumeUsed("/")) used")
                targetRow(.home, subtitle: "\(NSHomeDirectory()) and all user data. \(volumeUsed(NSHomeDirectory())) used")
                targetRow(.folder, subtitle: customFolder?.path ?? "Pick any folder to analyze.")
                ForEach(volumes, id: \.path) { volume in
                    targetRow(.external, subtitle: "\(volume.path) — \(ByteFormatting.format(volume.used)) used of \(ByteFormatting.format(volume.total))", externalPath: volume.path)
                }
            }
            .frame(width: 380)
            Spacer()
            Button("Start Scan") {
                state.finishOnboarding()
                startChosenScan()
            }
            .accentCTA()
            .keyboardShortcut(.defaultAction)
            .disabled(!canStartScan)
            Spacer()
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: DesignTokens.Layout.onboardingWidth, height: 680)
        .onAppear { loadVolumes() }
    }

    private var canStartScan: Bool {
        switch selection {
        case .folder: return customFolder != nil
        case .external: return selectedExternalPath != nil
        default: return true
        }
    }

    private func targetRow(_ target: ScanTarget, subtitle: String, externalPath: String? = nil) -> some View {
        let isSelected: Bool = {
            if target == .external, let externalPath {
                return selection == .external && selectedExternalPath == externalPath
            }
            return selection == target
        }()
        return Button {
            selection = target
            if target == .folder { pickFolder() } else if let externalPath {
                selectedExternalPath = externalPath
            }
        } label: {
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: target.symbol)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title).font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(20)
            .background { MetalSurface(flatSide: .right, accent: DesignTokens.Palette.orange, active: isSelected) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customFolder = url
        } else if customFolder == nil {
            // Cancelled with nothing chosen: fall back to a valid target.
            selection = .fullMac
        }
    }

    private func startChosenScan() {
        switch selection {
        case .fullMac:
            state.startRealScan(root: URL(fileURLWithPath: "/"), label: "Full Mac")
        case .home:
            state.startRealScan(root: FileManager.default.homeDirectoryForCurrentUser, label: "Home Folder")
        case .folder:
            if let folder = customFolder {
                state.startRealScan(root: folder, label: folder.lastPathComponent)
            }
        case .external:
            if let path = selectedExternalPath, let volume = volumes.first(where: { $0.path == path }) {
                state.startRealScan(root: URL(fileURLWithPath: path), label: volume.name)
            }
        }
    }

    private func loadVolumes() {
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForOpportunisticUsageKey], options: [.skipHiddenVolumes]) else { return }
        var result: [(name: String, path: String, used: Int64, total: Int64)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForOpportunisticUsageKey, .volumeIsInternalKey]),
                  values.volumeIsInternal == false,
                  let total = values.volumeTotalCapacity
            else { continue }
            let free = Int64(values.volumeAvailableCapacityForOpportunisticUsage ?? 0)
            result.append((values.volumeName ?? url.lastPathComponent, url.path, Int64(total) - free, Int64(total)))
        }
        volumes = result
    }

    private func volumeUsed(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForOpportunisticUsageKey]),
              let total = values.volumeTotalCapacity
        else { return " size unknown" }
        let free = Int64(values.volumeAvailableCapacityForOpportunisticUsage ?? 0)
        return "~\(ByteFormatting.format(Int64(total) - free)) used"
    }
}

#Preview {
    ScanTargetView().environmentObject(AppState())
}
