import SwiftUI
import AppKit

// MARK: - §16 Applications View: real installed-app inventory + stale leftovers

struct ApplicationsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var inventory: AppInventoryService
    @State private var filter: AppFilter = .all
    @State private var selection: AppEntry? = nil

    enum AppFilter: String, CaseIterable {
        case all, large, stale, recent
        var title: String {
            switch self {
            case .all: return "All"
            case .large: return "Large (>1 GB)"
            case .stale: return "Stale"
            case .recent: return "Recently added"
            }
        }
    }

    private var source: [AppEntry] {
        inventory.apps
    }

    private var apps: [AppEntry] {
        let q = state.searchText.lowercased()
        var list = source
        switch filter {
        case .all: break
        case .large: list = list.filter { $0.totalBytes > 1_000_000_000 }
        case .stale: list = list.filter(\.isStale)
        case .recent: list = list.filter { ($0.installedDaysAgo ?? 9_999) <= 30 }
        }
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) } }
        if filter == .recent {
            return list.sorted { ($0.installedDaysAgo ?? 9_999) < ($1.installedDaysAgo ?? 9_999) }
        }
        return list.sorted { $0.totalBytes > $1.totalBytes }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("\(source.count) apps installed · \(source.reduce(0) { $0 + $1.totalBytes }.fileSizeString) total")
                    .font(.headline)
                if inventory.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning \(inventory.scannedCount)…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(inventory.apps.isEmpty ? "Scan Apps" : "Rescan") {
                    inventory.scan()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Picker("Filter", selection: $filter) {
                    ForEach(AppFilter.allCases, id: \.self) { f in
                        Text("\(f.title) (\(count(for: f)))").tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            List(apps, id: \.id, selection: $selection) { app in
                HStack(spacing: DesignTokens.Space.m) {
                    appIcon(for: app)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: DesignTokens.Space.s) {
                            Text(app.name).font(.body.weight(.medium))
                            if app.isStale {
                                Text("Stale")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(.capsule)
                            }
                        }
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Bundle: \(app.bundleBytes.fileSizeString) · Artifacts (\(app.artifacts.count)): \(app.artifactBytes.fileSizeString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(app.totalBytes.fileSizeString)
                        .font(.body.monospacedDigit())
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = app
                    state.selectedApp = app
                    state.selectedNode = ScanNode(
                        name: app.name, path: app.bundlePath.isEmpty ? app.bundleID : app.bundlePath,
                        sizeBytes: app.totalBytes, category: .applications, fileCount: max(app.artifacts.count, 1))
                }
                .contextMenu {
                    Button("Reveal in Finder") {
                        if !app.bundlePath.isEmpty {
                            NSWorkspace.shared.selectFile(app.bundlePath, inFileViewerRootedAtPath: "")
                        }
                    }
                    Divider()
                    Button("Clean Artifacts Only") {
                        for artifact in app.artifacts {
                            state.stage(source: "App Cleanup", path: artifact.path, bytes: artifact.bytes)
                        }
                        state.showCleanup = true
                    }
                    .disabled(app.artifacts.isEmpty)
                    Button(app.isStale ? "Remove Leftover Files" : "Uninstall (app + artifacts)") {
                        state.uninstallApp = app
                    }
                    Divider()
                    Button("Open App") {
                        if !app.bundlePath.isEmpty {
                            NSWorkspace.shared.open(URL(fileURLWithPath: app.bundlePath))
                        }
                    }
                    .disabled(app.bundlePath.isEmpty)
                    Button("Copy Bundle Identifier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(app.bundleID, forType: .string)
                    }
                    Divider()
                    Button("Info") {
                        selection = app
                        state.selectedApp = app
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding(DesignTokens.Space.m)
        .onAppear {
            // Scan once — never on every tab visit (this walks all bundles +
            // artifacts and was the main source of tab-switch lag).
            if inventory.apps.isEmpty && !inventory.isScanning {
                inventory.scan()
            }
        }
        .task(id: state.freedCount) {
            // A cleanup just moved app bundles/artifacts to Trash — refresh
            // the inventory so uninstalled apps disappear without a manual rescan.
            if state.freedCount > 0, !inventory.isScanning {
                inventory.scan()
            }
        }
        // NOTE: no onDisappear cancel — the scan keeps running in the
        // background so revisiting the tab is instant.
    }

    @ViewBuilder
    private func appIcon(for app: AppEntry) -> some View {
        if !app.bundlePath.isEmpty {
            Image(nsImage: Self.cachedIcon(for: app.bundlePath))
                .resizable()
        } else {
            Image(systemName: "trash.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }

    /// NSWorkspace.icon hits the disk — cache per bundle path (main-thread confined).
    private static var iconCache: [String: NSImage] = [:]
    private static func cachedIcon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = icon
        return icon
    }

    private func count(for filter: AppFilter) -> Int {
        switch filter {
        case .all: return source.count
        case .large: return source.filter { $0.totalBytes > 1_000_000_000 }.count
        case .stale: return source.filter(\.isStale).count
        case .recent: return source.filter { ($0.installedDaysAgo ?? 9_999) <= 30 }.count
        }
    }
}

#Preview {
    ApplicationsView()
        .environmentObject(AppState())
        .environmentObject(AppInventoryService())
        .frame(width: 800, height: 600)
}
