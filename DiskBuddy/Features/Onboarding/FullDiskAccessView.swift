import SwiftUI

// MARK: - §02 Full Disk Access: real permission probe + polling on reactivation

struct FullDiskAccessView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsService

    var body: some View {
        VStack(spacing: DesignTokens.Space.l) {
            WizardHeader(
                step: 2,
                totalSteps: 3,
                onBack: {
                    withAnimation(.easeOut(duration: DesignTokens.Motion.base)) {
                        state.onboardingStep = .welcome
                    }
                }) {
                state.limitedMode = true
                state.finishOnboarding()
            }
            Spacer()
            Image(systemName: "folder.fill.badge.magnifyingglass")
                .font(.system(size: 80))
                .symbolRenderingMode(.hierarchical)
            Text("DiskDoom needs Full Disk Access")
                .font(.title2.weight(.semibold))
            Text("To find every hidden cache, leftover log, and stale preference file across your Mac, DiskDoom needs permission to read system and library folders. This happens in System Settings — DiskBuddy will open it for you.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            VStack(alignment: .leading, spacing: DesignTokens.Space.xs) {
                Text("What DiskDoom will do:").font(.callout.weight(.semibold))
                Label("Read file sizes and names", systemImage: "checkmark").foregroundStyle(.green)
                Label("Identify which apps left files", systemImage: "checkmark").foregroundStyle(.green)
                Label("Never modify files without your explicit approval", systemImage: "xmark").foregroundStyle(.secondary)
            }
            .font(.callout)
            .frame(width: 380, alignment: .leading)
            .specCard()
            Spacer()
            if permissions.fdaGranted {
                Button("Continue") {
                    withAnimation(.easeOut(duration: DesignTokens.Motion.base)) {
                        state.onboardingStep = .scanTarget
                    }
                }
                .accentCTA()
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Open System Settings") {
                    permissions.openPrivacySettings()
                }
                .accentCTA()
                .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: DesignTokens.Space.s) {
                Circle()
                    .fill(permissions.fdaGranted ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(permissions.fdaGranted ? "Status: Granted ✓" : "Status: Waiting for permission… (checked when you return)")
                    .font(.caption)
                    .foregroundStyle(permissions.fdaGranted ? .green : .secondary)
                Button("Check Again") { permissions.checkAll() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Button("Skip for now →") {
                state.limitedMode = true
                state.finishOnboarding() // user folders only, no /Library
            }
            .buttonStyle(.link)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: DesignTokens.Layout.onboardingWidth, height: 620)
        .onAppear {
            permissions.checkAll()
            if permissions.fdaGranted {
                state.onboardingStep = .scanTarget
            }
        }
    }
}

#Preview {
    FullDiskAccessView()
        .environmentObject(AppState())
        .environmentObject(PermissionsService())
}
