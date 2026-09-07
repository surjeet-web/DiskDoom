import SwiftUI

// MARK: - §31 Error States + §32 Empty States (reusable cards)

struct ErrorCard: View {
    let symbol: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(tint)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// §31A — Full Disk Access denied / limited mode.
struct FDADeniedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            ErrorCard(
                symbol: "lock.fill",
                title: "Full Disk Access Required",
                message: "DiskBuddy needs Full Disk Access to scan system folders and application caches. Without it, only user-selected folders can be scanned.",
                tint: .orange)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Scan Home Folder Only") {
                state.limitedMode = false
                state.startScan(target: "Home Folder")
            }
            .buttonStyle(.bordered)
        }
    }
}

// §31B — Scan failed (partial results available).
struct ScanFailedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            ErrorCard(
                symbol: "exclamationmark.triangle.fill",
                title: "Scan Interrupted",
                message: "An error occurred while scanning: \"Operation not permitted: /private/var/db/\". Partial results (\(state.scanFiles.formatted()) files) are available.",
                tint: .orange)
            Button("Retry Scan") {
                state.startScan()
            }
            .buttonStyle(.borderedProminent)
            Button("View Partial Results") {
                state.scanPhase = .done
                state.selectedNode = MockScanData.topLevel.first
            }
            .buttonStyle(.bordered)
        }
    }
}

// §26 Quick Look panel (prototype sheet).

struct QuickLookSheet: View {
    @EnvironmentObject var state: AppState
    let node: ScanNode

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: node.category.symbol)
                .font(.system(size: 96))
                .foregroundStyle(node.category.color)
            Text(URL(fileURLWithPath: node.path).lastPathComponent)
                .font(.title3.weight(.semibold))
            Text("\(node.sizeString) · Modified: Today 2:30 PM")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(node.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Button("Done") { state.quickLookNode = nil }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 480, height: 440)
    }
}
