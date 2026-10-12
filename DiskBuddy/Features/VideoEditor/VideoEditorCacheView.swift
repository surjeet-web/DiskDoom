import SwiftUI
import AppKit

// MARK: - Video editor caches view (render/proxy/peak caches + safe in-app tips)

/// Process-wide scan state for the video editor caches tab.
///
/// WHY not view-local `@State`: `MainWindowView` applies `.id(state.sidebarTab)`
/// to the detail pane, which *destroys* this view (and any `@State` /
/// `@StateObject` it owns) on every sidebar tab switch — so returning to this
/// tab re-walked every video cache path. A shared main-actor store survives view
/// teardown, so the walk happens once per app session.
@MainActor
final class VideoEditorCacheStore: ObservableObject {
    static let shared = VideoEditorCacheStore()

    @Published private(set) var results: [VideoScanResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var totalSize: Int64 = 0

    private var task: Task<Void, Never>?
    /// Explicit flag the detached walk reads. `Task.isCancelled` inside
    /// `Task.detached` is never set, so cancel used to be a complete no-op.
    private var token = ScanCancellation()
    private var didScan = false

    /// Wall-clock budget for one pass over the registry.
    private static let scanBudget: TimeInterval = 30

    private init() {}

    /// At most one walk at a time; `force` is the "Rescan" button.
    func scan(force: Bool = false) {
        if isScanning { return }
        // Only a *completed* scan latches, so a walk cancelled by tabbing away
        // is retried when the user comes back.
        if didScan && !force { return }

        task?.cancel()
        token.cancel()
        let token = ScanCancellation()
        self.token = token
        isScanning = true
        task = Task { [weak self] in
            let deadline = Date().addingTimeInterval(Self.scanBudget)
            let found: [VideoScanResult] = await Task.detached {
                var all: [VideoScanResult] = []
                walk: for definition in VideoEditorCacheRegistry.all {
                    for cachePath in definition.paths {
                        if token.isCancelled { break walk }
                        if Date() >= deadline { break walk }
                        for path in ProCacheScanner.expandGlob(cachePath.path) {
                            if token.isCancelled { break walk }
                            let measurement = ProCacheScanner.measure(path: path)
                            guard measurement.bytes > 0 else { continue }
                            all.append(VideoScanResult(
                                definition: definition,
                                path: path,
                                size: measurement.bytes,
                                fileCount: measurement.files))
                        }
                    }
                }
                return all.sorted { $0.size > $1.size }
            }.value
            guard let self, !token.isCancelled else { return }
            results = found
            totalSize = found.reduce(Int64(0)) { $0 + $1.size }
            isScanning = false
            didScan = true
            task = nil
        }
    }

    func cancel() {
        token.cancel()
        task?.cancel()
        task = nil
        isScanning = false
    }
}

struct VideoEditorCacheView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var store = VideoEditorCacheStore.shared

    private var results: [VideoScanResult] { store.results }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isScanning {
                ProgressView("Scanning video editor caches…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Video Editor Caches Found").font(.title3)
                    Text("No known video application caches (Final Cut Pro, Premiere, After Effects, DaVinci Resolve, Motion, Compressor, Shotcut, HandBrake) exist on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                    Button("Rescan") { store.scan(force: true) }.buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(results) { result in
                    VideoCacheRow(result: result) {
                        state.stage(source: "Video Caches", path: result.path, bytes: result.size)
                        state.showCleanup = true
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .task { store.scan() }
        .onDisappear { store.cancel() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Editor Caches").font(.title2.weight(.semibold))
                Text("\(results.count) cache locations")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(ByteFormatting.format(store.totalSize))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(store.totalSize > 100_000_000_000 ? .red : .orange)
                Text("total video cache")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                store.scan(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isScanning)
        }
        .padding(DesignTokens.Space.l)
    }
}

struct VideoScanResult: Identifiable {
    let id = UUID()
    let definition: VideoEditorCacheDefinition
    let path: String
    let size: Int64
    let fileCount: Int
    var sizeFormatted: String { ByteFormatting.format(size) }
}

// MARK: - Row

private struct VideoCacheRow: View {
    let result: VideoScanResult
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: result.definition.icon)
                .font(.title2)
                .foregroundStyle(result.definition.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.definition.name).font(.callout.weight(.semibold))
                    riskBadge
                    if result.size > 50_000_000_000 {
                        Text("HUGE")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.red.opacity(0.2), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text(result.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.definition.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                    Text(result.definition.managementTip)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(result.sizeFormatted)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(result.size > 50_000_000_000 ? .red : .orange)
                Text("\(result.fileCount.formatted()) files")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)

            VStack(spacing: 4) {
                if result.definition.cleanMethod == .trash && result.size > 0 {
                    // Only offer a one-click delete when the definition is
                    // actually safe. `.caution` entries can point at folders
                    // holding unsaved work (the After Effects auto-save
                    // directory is one), and tinting them orange while still
                    // enabling the button destroyed user data.
                    if result.definition.riskLevel == .safe {
                        Button("Clean", action: onClean)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.green)
                    } else {
                        Button("Review…", action: onClean)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.orange)
                            .help(result.definition.riskLevel == .caution
                                  ? "This location may contain unsaved work — you'll confirm each item."
                                  : "Large but safe to remove — this may take a while.")
                    }
                }
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: result.path))
                } label: {
                    Image(systemName: "folder").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Open in Finder")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var riskBadge: some View {
        Text(result.definition.riskLevel.badge)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(result.definition.riskLevel.color.opacity(0.15), in: Capsule())
            .foregroundStyle(result.definition.riskLevel.color)
    }
}

#Preview {
    VideoEditorCacheView()
        .environmentObject(AppState())
        .frame(width: 900, height: 620)
}
