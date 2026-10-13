import SwiftUI
import AppKit

// MARK: - Developer Workspace view (projects tab + global caches tab)

struct DeveloperWorkspaceView: View {
    @EnvironmentObject var scanner: DeveloperWorkspaceScanner
    @EnvironmentObject var state: AppState
    @State private var selectedProject: DevProject?
    @State private var showCleanConfirmation = false
    @State private var projectToClean: DevProject?

    var body: some View {
        VStack(spacing: 0) {
            devHeader
            Divider()
            TabView {
                projectsTab
                    .tabItem { Label("Projects", systemImage: "folder.fill") }
                DevCacheView()
                    .tabItem { Label("Global Caches", systemImage: "externaldrive.fill") }
            }
        }
        .task {
            if scanner.projects.isEmpty, !scanner.isScanning {
                scanner.scan()
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDetailSheet(project: project)
        }
        .alert("Clean Project Caches?", isPresented: $showCleanConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let project = projectToClean {
                    cleanProject(project)
                }
            }
        } message: {
            if let project = projectToClean {
                Text("Moves \(project.cleanableFormatted) of build artifacts, caches and dependencies from \(project.name) to the Trash. Source code and .git are untouched. Rebuilds will take time.")
            }
        }
    }

    // MARK: - Header

    private var devHeader: some View {
        HStack(spacing: DesignTokens.Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Developer Workspace").font(.title2.weight(.semibold))
                Text(scanner.isScanning ? "Scanning…" : scanner.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: DesignTokens.Space.xl) {
                StatColumn(label: "Projects", value: "\(scanner.projects.count)", color: .blue)
                StatColumn(label: "Total", value: ByteFormatting.format(scanner.totalProjectSize), color: .primary)
                StatColumn(label: "Cleanable", value: ByteFormatting.format(scanner.totalCleanableSize), color: .orange)
            }
            Button {
                scanner.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(scanner.isScanning)
        }
        .padding(DesignTokens.Space.l)
    }

    // MARK: - Projects tab

    private var projectsTab: some View {
        Group {
            if scanner.projects.isEmpty && !scanner.isScanning {
                emptyProjectsView
            } else {
                List(scanner.projects) { project in
                    ProjectRow(
                        project: project,
                        onTap: { selectedProject = project },
                        onClean: {
                            projectToClean = project
                            showCleanConfirmation = true
                        })
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var emptyProjectsView: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Projects Found").font(.title3)
            Text("DiskDoom scans ~/Developer, ~/Projects, ~/Code, ~/Documents and ~/Desktop for development projects (Xcode, Node, Rust, Go, Python, Unity, Unreal…).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Choose Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = true
                if panel.runModal() == .OK {
                    scanner.scan(searchPaths: panel.urls.map(\.path))
                }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clean (routes through the shared Trash queue)

    private func cleanProject(_ project: DevProject) {
        for component in project.components where component.canClean && component.size > 0 {
            state.stage(source: "Dev Project", path: component.path, bytes: component.size)
        }
        state.showCleanup = true
    }
}

// MARK: - Header stat

private struct StatColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Project row

private struct ProjectRow: View {
    let project: DevProject
    let onTap: () -> Void
    let onClean: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignTokens.Space.m) {
                Image(systemName: project.type.icon)
                    .font(.title2)
                    .foregroundStyle(project.type.color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name).font(.callout.weight(.semibold))
                        Text(project.type.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(project.type.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(project.type.color)
                        if project.isStale {
                            Text("Stale")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if project.totalFootprint > 0 {
                    componentMiniBar.frame(width: 80)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(project.totalFormatted)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    if project.cleanableSize > 0 {
                        Text("\(project.cleanableFormatted) cleanable")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                    }
                }
                .frame(width: 95, alignment: .trailing)

                if project.cleanableSize > 1_000_000 {
                    Button(action: onClean) {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Clean \(project.cleanableFormatted) of caches")
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Source (blue) / deps (purple) / build (orange) / cache (red) / other (gray).
    private var componentMiniBar: some View {
        GeometryReader { geo in
            let total = max(project.totalFootprint, 1)
            let sourceSize = project.components
                .filter { $0.category == .source || $0.category == .config }
                .reduce(Int64(0)) { $0 + $1.size }
            let depSize = project.components
                .filter { $0.category == .dependencies }
                .reduce(Int64(0)) { $0 + $1.size }
            let otherSize = max(0, project.totalFootprint - sourceSize - depSize - project.buildSize - project.cacheSize)
            HStack(spacing: 1) {
                if sourceSize > 0 {
                    Rectangle().fill(.blue.opacity(0.5))
                        .frame(width: max(geo.size.width * CGFloat(sourceSize) / CGFloat(total), 1))
                }
                if depSize > 0 {
                    Rectangle().fill(.purple.opacity(0.5))
                        .frame(width: max(geo.size.width * CGFloat(depSize) / CGFloat(total), 1))
                }
                if project.buildSize > 0 {
                    Rectangle().fill(.orange.opacity(0.5))
                        .frame(width: max(geo.size.width * CGFloat(project.buildSize) / CGFloat(total), 1))
                }
                if project.cacheSize > 0 {
                    Rectangle().fill(.red.opacity(0.4))
                        .frame(width: max(geo.size.width * CGFloat(project.cacheSize) / CGFloat(total), 1))
                }
                if otherSize > 0 {
                    Rectangle().fill(.gray.opacity(0.3))
                        .frame(width: max(geo.size.width * CGFloat(otherSize) / CGFloat(total), 1))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(height: 8)
    }
}

// MARK: - Project detail sheet

private struct ProjectDetailSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var overlays: OverlayStack
    let project: DevProject
    @Environment(\.dismiss) private var dismiss
    @State private var sortOrder = SortOrder.size

    enum SortOrder: String, CaseIterable {
        case size = "Size", name = "Name", category = "Category"
    }

    var body: some View {
        VStack(spacing: DesignTokens.Space.l) {
            ModalHeader(title: "Project Details", overlayID: "project-detail") { dismiss() }
            HStack {
                Image(systemName: project.type.icon)
                    .font(.largeTitle)
                    .foregroundStyle(project.type.color)
                VStack(alignment: .leading) {
                    Text(project.name).font(.title2.weight(.semibold))
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }

            HStack(spacing: DesignTokens.Space.xl) {
                DetailStat(label: "Total", value: project.totalFormatted)
                DetailStat(label: "Build", value: project.buildFormatted, color: .orange)
                DetailStat(label: "Caches", value: project.cacheFormatted, color: .red)
                DetailStat(label: "Cleanable", value: project.cleanableFormatted, color: .green)
            }

            Divider()

            HStack {
                Text("Components").font(.headline)
                Spacer()
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            List(sortedComponents) { component in
                HStack(spacing: DesignTokens.Space.m) {
                    Image(systemName: component.category.icon)
                        .foregroundStyle(component.canClean ? .orange : .secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text(component.name).font(.callout.weight(.medium))
                        Text(component.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(component.category.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if component.canClean {
                        Text(component.cleanRisk.label)
                            .font(.caption2)
                            .foregroundStyle(component.cleanRisk.color)
                            .frame(width: 140, alignment: .leading)
                    }
                    Text(component.sizeFormatted)
                        .font(.callout.monospacedDigit())
                        .frame(width: 72, alignment: .trailing)
                    if component.canClean && component.size > 0 {
                        Button("Stage") {
                            state.stage(source: "Dev Project", path: component.path, bytes: component.size)
                            state.showCleanup = true
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .onAppear { overlays.present("project-detail") }
        .onDisappear { overlays.dismiss("project-detail") }
        .padding()
        .frame(width: 720, height: 520)
    }

    private var sortedComponents: [ProjectComponent] {
        switch sortOrder {
        case .size: return project.components.sorted { $0.size > $1.size }
        case .name: return project.components.sorted { $0.name < $1.name }
        case .category: return project.components.sorted { $0.category.rawValue < $1.category.rawValue }
        }
    }
}

private struct DetailStat: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DeveloperWorkspaceView()
        .environmentObject(DeveloperWorkspaceScanner())
        .environmentObject(AppState())
        .frame(width: 900, height: 620)
}
