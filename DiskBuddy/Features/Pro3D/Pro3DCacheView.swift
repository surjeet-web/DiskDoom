import SwiftUI
import AppKit

// MARK: - 3D & Creative app caches view

/// Process-wide scan state for the 3D caches tab.
///
/// WHY not view-local `@State`: `MainWindowView` applies `.id(state.sidebarTab)`
/// to the detail pane, which *destroys* this view (and any `@State` /
/// `@StateObject` it owns) on every sidebar tab switch — so coming back to this
/// tab re-walked every 3D cache path from scratch. A shared main-actor store
/// survives view teardown, so the walk happens once per app session.
@MainActor
final class Pro3DCacheStore: ObservableObject {
    static let shared = Pro3DCacheStore()

    @Published private(set) var results: [Pro3DScanResult] = []
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
            let found: [Pro3DScanResult] = await Task.detached {
                var all: [Pro3DScanResult] = []
                walk: for definition in Pro3DCacheRegistry.all {
                    for cachePath in definition.cachePaths {
                        if token.isCancelled { break walk }
                        if Date() >= deadline { break walk }
                        for path in ProCacheScanner.expandGlob(cachePath.path) {
                            if token.isCancelled { break walk }
                            let measurement = ProCacheScanner.measure(path: path)
                            guard measurement.bytes > 0 else { continue }
                            all.append(Pro3DScanResult(
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

struct Pro3DCacheView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var store = Pro3DCacheStore.shared
    @State private var selectedApp: String?

    private var results: [Pro3DScanResult] { store.results }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            appFilterBar
            Divider()
            if store.isScanning {
                ProgressView("Scanning 3D application caches…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No 3D App Caches Found").font(.title3)
                    Text("No known 3D/creative application caches (Blender, Maya, Houdini, Cinema 4D, Unreal, Unity, Substance, ZBrush) exist on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Rescan") { store.scan(force: true) }.buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                resultList
            }
        }
        .task { store.scan() }
        .onDisappear { store.cancel() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("3D & Creative App Caches").font(.title2.weight(.semibold))
                Text("\(results.count) cache locations found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormatting.format(store.totalSize))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(store.totalSize > 50_000_000_000 ? .red : .orange)
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

    private var appFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Space.s) {
                FilterChip(label: "All", isSelected: selectedApp == nil, color: .accentColor) {
                    selectedApp = nil
                }
                let apps = Set(results.map { $0.definition.appName })
                ForEach(Array(apps).sorted(), id: \.self) { app in
                    let size = results.filter { $0.definition.appName == app }.reduce(Int64(0)) { $0 + $1.size }
                    FilterChip(
                        label: "\(app) (\(ByteFormatting.format(size)))",
                        isSelected: selectedApp == app,
                        color: results.first { $0.definition.appName == app }?.definition.color ?? .secondary) {
                        selectedApp = selectedApp == app ? nil : app
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Space.m)
            .padding(.vertical, DesignTokens.Space.s)
        }
        .background(Color.secondary.opacity(0.03))
    }

    private var resultList: some View {
        List(filteredResults) { result in
            Pro3DCacheRow(result: result) {
                state.stage(source: "3D Caches", path: result.path, bytes: result.size)
                state.showCleanup = true
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var filteredResults: [Pro3DScanResult] {
        if let selected = selectedApp {
            return results.filter { $0.definition.appName == selected }
        }
        return results
    }
}

private struct Pro3DCacheRow: View {
    let result: Pro3DScanResult
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: result.definition.icon)
                .font(.title3)
                .foregroundStyle(result.definition.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.definition.name)
                    .font(.callout.weight(.medium))
                Text(result.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.definition.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            riskBadge

            if result.fileCount > 0 {
                Text("\(result.fileCount.formatted()) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            Text(result.sizeFormatted)
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(result.size > 10_000_000_000 ? .red : .orange)
                .frame(width: 72, alignment: .trailing)

            if result.size > 0 && result.definition.cleanMethod == .trash {
                // Gate on risk: `.caution` entries can point at folders with
                // unsaved work, so they must never get an enabled one-click
                // trash button.
                Button(action: onClean) {
                    Image(systemName: result.definition.riskLevel == .safe
                          ? "trash" : "exclamationmark.triangle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(result.definition.riskLevel == .safe ? .green : .orange)
                .help(result.definition.riskLevel == .safe
                      ? "Move \(result.sizeFormatted) to the cleanup queue"
                      : "Caution — may contain unsaved work. You'll confirm each item.")
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
        .padding(.vertical, 2)
    }

    private var riskBadge: some View {
        Text(result.definition.riskLevel.badge)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(result.definition.riskLevel.color.opacity(0.15), in: Capsule())
            .foregroundStyle(result.definition.riskLevel.color)
    }
}

struct Pro3DScanResult: Identifiable {
    let id = UUID()
    let definition: Pro3DCacheDefinition
    let path: String
    let size: Int64
    let fileCount: Int
    var sizeFormatted: String { ByteFormatting.format(size) }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : .primary)
    }
}

#Preview {
    Pro3DCacheView()
        .environmentObject(AppState())
        .frame(width: 900, height: 620)
}
