import SwiftUI

// MARK: - §02 Onboarding: Full Disk Access Explainer (prototype: simulated status)

struct FullDiskAccessView: View {
    @EnvironmentObject var state: AppState
    @State private var status: FDAStatus = .waiting
    @State private var pollTask: Task<Void, Never>?

    enum FDAStatus {
        case waiting, checking, granted

        var text: String {
            switch self {
            case .waiting: return "Status: Waiting for permission…"
            case .checking: return "Status: Checking…"
            case .granted: return "Status: Granted ✓"
            }
        }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.l) {
            Spacer()
            Image(systemName: "folder.fill.badge.magnifyingglass")
                .font(.system(size: 80))
                .symbolRenderingMode(.hierarchical)
            Text("DiskBuddy needs Full Disk Access")
                .font(.title2.weight(.semibold))
            Text("To find every hidden cache, leftover log, and stale preference file across your Mac, DiskBuddy needs permission to read system and library folders. This happens in System Settings — DiskBuddy will open it for you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Text("What DiskBuddy will do:").font(.callout.weight(.semibold))
                Label("Read file sizes and names", systemImage: "checkmark").foregroundStyle(.green)
                Label("Identify which apps left files", systemImage: "checkmark").foregroundStyle(.green)
                Label("Never modify files without your explicit approval", systemImage: "xmark").foregroundStyle(.secondary)
            }
            .font(.callout)
            .frame(width: 380, alignment: .leading)
            .specCard()
            Spacer()
            if status == .granted {
                Button("Continue") {
                    withAnimation(.easeOut(duration: DesignTokens.Motion.base)) {
                        state.onboardingStep = .scanTarget
                    }
                }
                .accentCTA()
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Open System Settings") {
                    status = .checking
                    // Prototype: simulate the polling loop (spec: 1.5s poll).
                    pollTask?.cancel()
                    pollTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if !Task.isCancelled { status = .granted }
                    }
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .accentCTA()
                .keyboardShortcut(.defaultAction)
            }
            Text(status.text)
                .font(.caption)
                .foregroundStyle(status == .granted ? .green : .secondary)
            Button("Skip for now →") {
                state.finishOnboarding() // limited mode: user folders only
            }
            .buttonStyle(.link)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: DesignTokens.Layout.onboardingWidth, height: 620)
        .onDisappear { pollTask?.cancel() }
    }
}

#Preview {
    FullDiskAccessView().environmentObject(AppState())
}
