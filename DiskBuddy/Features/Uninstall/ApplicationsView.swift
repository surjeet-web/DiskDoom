import SwiftUI

// MARK: - §16 Applications View: app list (mock data)

struct ApplicationsView: View {
    @EnvironmentObject var state: AppState
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

    private var apps: [AppEntry] {
        let q = state.searchText.lowercased()
        var list = MockApps.all
        switch filter {
        case .all: break
        case .large: list = list.filter { $0.totalBytes > 1_000_000_000 }
        case .stale: list = list.filter(\.isStale)
        case .recent: list = list.sorted { $0.installedDaysAgo < $1.installedDaysAgo }
        }
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) } }
        return list.sorted { $0.totalBytes > $1.totalBytes }
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack {
                Text("\(MockApps.all.count) apps installed · \(MockApps.all.reduce(0) { $0 + $1.totalBytes }.fileSizeString) total")
                    .font(.headline)
                Spacer()
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
                    Image(systemName: app.symbol)
                        .font(.title2)
                        .foregroundStyle(app.tint)
                        .frame(width: 32)
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
                        Text("Bundle: \(app.bundleBytes.fileSizeString) · Artifacts: \(app.artifactBytes.fileSizeString)")
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
                    state.selectedNode = ScanNode(
                        name: app.name, path: "/Applications/\(app.name).app",
                        sizeBytes: app.totalBytes, category: .applications, fileCount: 12_400)
                }
                .contextMenu {
                    Button("Reveal in Finder") { }
                    Divider()
                    Button("Clean Artifacts Only") {
                        state.stage(source: "App Cleanup", path: "\(app.name) artifacts", bytes: app.artifactBytes)
                        state.showCleanup = true
                    }
                    Button("Uninstall (app + artifacts)") {
                        state.uninstallApp = app
                    }
                    Divider()
                    Button("Open App") { }
                    Button("Copy Bundle Identifier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(app.bundleID, forType: .string)
                    }
                    Divider()
                    Button("Info") { selection = app }
                }
            }
            .listStyle(.plain)
        }
        .padding(DesignTokens.Space.m)
    }

    private func count(for filter: AppFilter) -> Int {
        switch filter {
        case .all: return MockApps.all.count
        case .large: return MockApps.all.filter { $0.totalBytes > 1_000_000_000 }.count
        case .stale: return MockApps.all.filter(\.isStale).count
        case .recent: return MockApps.all.count
        }
    }
}

#Preview {
    ApplicationsView().environmentObject(AppState())
        .frame(width: 800, height: 600)
}
