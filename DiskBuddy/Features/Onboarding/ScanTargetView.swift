import SwiftUI

// MARK: - §03 Onboarding: Scan Target Selection (prototype: static volumes)

struct ScanTargetView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: ScanTarget = .fullMac
    @State private var includeSnapshots = false

    private var targetName: String { selection.scanName }

    enum ScanTarget: String, CaseIterable, Identifiable {
        case fullMac, home, folder, external
        var id: String { rawValue }

        var scanName: String {
            switch self {
            case .fullMac: return "Full Mac"
            case .home: return "Home Folder"
            case .folder: return "~/Documents"
            case .external: return "/Volumes/Backup"
            }
        }

        var title: String {
            switch self {
            case .fullMac: return "Full Mac"
            case .home: return "Home Folder"
            case .folder: return "Choose Folder…"
            case .external: return "External Volume"
            }
        }

        var subtitle: String {
            switch self {
            case .fullMac: return "Everything — system, apps, user folders, caches. ~256 GB used"
            case .home: return "~/ and all user data. ~82 GB used"
            case .folder: return "Pick any folder to analyze."
            case .external: return "/Volumes/Backup — 1.2 TB used"
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
            Text("What do you want to scan?")
                .font(.title2.weight(.semibold))
                .padding(.top, DesignTokens.Space.xl)
            VStack(spacing: DesignTokens.Space.s) {
                ForEach(ScanTarget.allCases) { target in
                    Button {
                        selection = target
                    } label: {
                        HStack(spacing: DesignTokens.Space.m) {
                            Image(systemName: target.symbol)
                                .font(.title2)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.title).font(.body.weight(.medium))
                                Text(target.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
            }
            .frame(width: 380)
            Toggle("Include system snapshots (APFS/Time Machine)", isOn: $includeSnapshots)
                .font(.caption)
                .frame(width: 380, alignment: .leading)
            Spacer()
            Button("Start Scan") {
                state.finishOnboarding()
                state.startScan(target: targetName)
            }
            .accentCTA()
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: DesignTokens.Layout.onboardingWidth, height: 680)
    }
}

#Preview {
    ScanTargetView().environmentObject(AppState())
}
