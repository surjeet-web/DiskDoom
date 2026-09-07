import SwiftUI
import AppKit

// MARK: - §03 Scan Target Selection (real volumes, real folder picker)

struct ScanTargetView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: ScanTarget = .fullMac
    @State private var includeSnapshots = false
    @State private var customFolder: URL? = nil
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
                state.limitedMode = true
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
                    targetRow(.external, subtitle: "\(volume.path) — \(ByteFormatting.format(volume.used)) used of \(ByteFormatting.format(volume.total))")
                }
            }
            .frame(width: 380)
            Toggle("Include system snapshots (APFS/Time Machine)", isOn: $includeSnapshots)
                .font(.caption)
                .frame(width: 380, alignment: .leading)
            Spacer()
            Button("Start Scan") {
                state.finishOnboarding()
                startChosenScan()
            }
            .accentCTA()
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: DesignTokens.Layout.onboardingWidth, height: 680)
        .onAppear { loadVolumes() }
    }

    private func targetRow(_ target: ScanTarget, subtitle: String) -> some View {
        Button {
            selection = target
            if target == .folder { pickFolder() }
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
                Image(systemName: selection == target ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == target ? Color.accentColor : .secondary)
            }
            .padding(DesignTokens.Space.m)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                    .stroke(selection == target ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            customFolder = panel.url
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
            } else {
                state.startRealScan(root: FileManager.default.homeDirectoryForCurrentUser, label: "Home Folder")
            }
        case .external:
            if let first = volumes.first {
                state.startRealScan(root: URL(fileURLWithPath: first.path), label: first.name)
            } else {
                state.startRealScan(root: URL(fileURLWithPath: "/"), label: "Full Mac")
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
