import SwiftUI
import AppKit

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
                message: "DiskDoom needs Full Disk Access to scan system folders and application caches. Without it, only user-selected folders can be scanned.",
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

// §31B — Scan failed (real skipped-directory report + partial results).

struct ScanFailedView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            ErrorCard(
                symbol: "exclamationmark.triangle.fill",
                title: state.scanRoot == nil ? "Scan Failed" : "Scan Incomplete",
                message: state.scanRoot == nil
                    ? "Nothing could be read at \"\(state.scanTargetName)\". External volumes usually need Full Disk Access or an admin-approved mount."
                    : "\(state.skippedPaths.count) folders couldn't be read. Partial results (\(state.scanRoot!.fileCount.formatted()) files) are available below.",
                tint: .orange)
            if !state.skippedPaths.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(state.skippedPaths.prefix(20), id: \.self) { skipped in
                            Text(skipped)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if state.skippedPaths.count > 20 {
                            Text("…and \(state.skippedPaths.count - 20) more")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(DesignTokens.Space.m)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(.rect(cornerRadius: DesignTokens.Radius.m))
                }
                .frame(maxWidth: 560, maxHeight: 200)
            }
            Button("Retry Scan") {
                state.retryScan()
            }
            .buttonStyle(.borderedProminent)
            if state.scanRoot != nil {
                Button("View Partial Results") {
                    state.scanPhase = .done
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// §26 Quick Look panel (real icon + real filesystem metadata).

struct QuickLookSheet: View {
    @EnvironmentObject var state: AppState
    let node: ScanNode

    private var fileURL: URL {
        URL(fileURLWithPath: (node.path as NSString).expandingTildeInPath)
    }

    private var attributes: [FileAttributeKey: Any] {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .frame(width: 96, height: 96)
            Text(fileURL.lastPathComponent)
                .font(.title3.weight(.semibold))
            Text("\(node.sizeString) · Modified: \((attributes[.modificationDate] as? Date)?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(node.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
            }
            .buttonStyle(.bordered)
            Button("Done") { state.quickLookNode = nil }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(DesignTokens.Space.xl)
        .frame(width: 480, height: 480)
    }
}
