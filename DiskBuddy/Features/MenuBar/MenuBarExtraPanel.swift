import SwiftUI

// MARK: - Feature 6: Menu bar dropdown panel (window-style MenuBarExtra)

struct MenuBarExtraPanel: View {
    @EnvironmentObject var monitor: MenuBarMonitor
    @EnvironmentObject var state: AppState
    @EnvironmentObject var forecastEngine: DiskForecastEngine
    @EnvironmentObject var gamification: GamificationEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            spaceGauge
                .padding(DesignTokens.Space.m)

            Divider()
            gamificationRow
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, DesignTokens.Space.s)

            Divider()
            quickStatsRow
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, DesignTokens.Space.s)

            if !monitor.topSpaceHogs.isEmpty {
                Divider()
                spaceHogsSection
            }

            if let forecast = forecastEngine.forecast, let days = forecast.daysUntilFull {
                Divider()
                forecastRow(days: days)
            }

            Divider()
            actionButtons
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, DesignTokens.Space.s)

            Divider()
            footerRow
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.vertical, DesignTokens.Space.s)
        }
        .frame(width: 320)
        .padding(16)
        .background { MetalSurface(family: .well, flatSide: .top, depth: 6, accent: DesignTokens.Palette.orange) }
        .preferredColorScheme(.dark)
        .onAppear {
            monitor.pollDiskSpace()
            monitor.refreshQuickFolderStats(force: false)
        }
    }

    // MARK: - Space gauge

    @ViewBuilder
    private var capacityRing: some View {
        if let capacity = monitor.currentCapacity.availableValue {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: capacity.usedPercent / 100)
                    .stroke(monitor.spaceState.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(100 - capacity.usedPercent))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(monitor.spaceState.color)
            }
            .frame(width: 56, height: 56)
            .accessibleProgress(value: capacity.usedPercent / 100,
                label: "Disk usage: \(ByteFormatting.format(capacity.usedBytes)) used of \(ByteFormatting.format(capacity.totalBytes)), \(ByteFormatting.format(capacity.freeBytes)) free")
        } else {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 8)
                Text("—").font(.caption)
            }
            .frame(width: 56, height: 56)
            .accessibilityLabel("Disk capacity: \(monitor.currentCapacity.statusLabel)")
        }
    }

    private var spaceGauge: some View {
        HStack(spacing: DesignTokens.Space.m) {
            capacityRing

            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.currentCapacity.availableValue.map { ByteFormatting.format($0.freeBytes) } ?? monitor.currentCapacity.statusLabel)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text(monitor.currentCapacity.availableValue.map { "free of \(ByteFormatting.format($0.totalBytes))" } ?? "Disk capacity unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.statusText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let grade = monitor.healthGrade {
                VStack(spacing: 2) {
                    Text(grade)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(gradeColor(grade))
                    Text("health")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(gradeColor(grade).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Gamification

    private var gamificationRow: some View {
        Button {
            openApp(tab: .progress)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("Level \(gamification.level)")
                            .font(.system(size: 11, weight: .semibold))
                        Text(gamification.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: gamification.progressToNextLevel)
                        .tint(.purple)
                        .frame(width: 150)
                }
                Spacer()
                Label("\(gamification.streak)", systemImage: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("\(gamification.xpToNextLevel) XP")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Progress — level, quests and achievements")
    }

    // MARK: - Quick stats

    private var quickStatsRow: some View {
        HStack(spacing: DesignTokens.Space.m) {
            StatPill(
                icon: "arrow.down.circle.fill",
                label: "Downloads",
                value: folderStat(monitor.downloadsBytes, partial: monitor.downloadsPartial),
                color: .purple)
            StatPill(
                icon: "trash.fill",
                label: "Trash",
                value: folderStat(monitor.trashBytes, partial: monitor.trashPartial),
                color: .gray)
            if let score = monitor.litterScore {
                StatPill(
                    icon: "trash.circle",
                    label: "Litter",
                    value: "\(score)/100",
                    color: score > 60 ? .red : score > 30 ? .orange : .green)
            } else {
                StatPill(
                    icon: "heart.text.square",
                    label: "Health",
                    value: monitor.healthGrade ?? "—",
                    color: .green)
            }
        }
    }

    private func folderStat(_ bytes: Int64, partial: Bool) -> String {
        if bytes < 0 { return "…" }
        if partial { return bytes == 0 ? "Not measured" : "≥ " + ByteFormatting.format(bytes) }
        return bytes == 0 ? "Empty" : ByteFormatting.format(bytes)
    }

    // MARK: - Space hogs

    private var spaceHogsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Top Space Hogs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                scanDateLabel
            }
            .padding(.horizontal, DesignTokens.Space.m)
            .padding(.top, DesignTokens.Space.s)

            ForEach(monitor.topSpaceHogs.prefix(6)) { hog in
                Button {
                    openApp(tab: .explore)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: hog.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(hog.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(hog.sizeFormatted)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, DesignTokens.Space.m)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(hog.path)
            }
            .padding(.bottom, DesignTokens.Space.s)
        }
    }

    // MARK: - Scan freshness

    /// WHY: the hogs above come from whichever scan produced them — possibly
    /// a cached snapshot restored at launch — so this must show the scan's
    /// real timestamp, not a relative "2 minutes ago" stamped when the
    /// monitor was last refreshed.
    @ViewBuilder
    private var scanDateLabel: some View {
        if let date = monitor.lastScanDate {
            if Date().timeIntervalSince(date) > 86_400 {
                // Older than 24 h: staleness must be visible at a glance.
                Text("Data from \(date.formatted(.relative(presentation: .named))) — rescan to refresh")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help("Scanned \(date.formatted(date: .abbreviated, time: .shortened)) — these sizes may be out of date")
            } else {
                Text("Data from \(date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Scanned \(date.formatted(date: .abbreviated, time: .shortened))")
            }
        } else {
            Text("no scan yet")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .help("No scan has run yet — no scan date to show")
        }
    }

    // MARK: - Forecast

    private func forecastRow(days: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: days <= 7 ? "exclamationmark.triangle.fill" : "chart.line.uptrend.xyaxis")
                .foregroundStyle(days <= 7 ? .red : .orange)
                .font(.caption)
            if days <= 7 {
                Text("Estimated full in ~\(days) days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Text("~\(days) days until full")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Details") {
                openApp(tab: .forecast)
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, DesignTokens.Space.m)
        .padding(.vertical, DesignTokens.Space.s)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: DesignTokens.Space.s) {
            HStack(spacing: DesignTokens.Space.s) {
                MenuBarButton(icon: "arrow.clockwise", label: "Quick Scan", color: .blue) {
                    openApp(tab: .explore)
                    state.startRealScan(root: FileManager.default.homeDirectoryForCurrentUser, label: "Home Folder")
                }
                MenuBarButton(icon: "bolt.fill", label: "What-If", color: .orange) {
                    openApp(tab: .simulator)
                }
                MenuBarButton(icon: "terminal.fill", label: "Dev Caches", color: .green) {
                    openApp(tab: .devCaches)
                }
            }
            HStack(spacing: DesignTokens.Space.s) {
                MenuBarButton(icon: "doc.on.doc.fill", label: "Duplicates", color: .purple) {
                    openApp(tab: .duplicates)
                }
                MenuBarButton(icon: "photo.on.rectangle.angled", label: "Photos", color: .pink) {
                    openApp(tab: .photos)
                }
                MenuBarButton(icon: "folder.fill", label: "Explorer", color: .cyan) {
                    openApp(tab: .folders)
                }
            }
            HStack(spacing: DesignTokens.Space.s) {
                MenuBarButton(icon: "trophy.fill", label: "Progress", color: .yellow) {
                    openApp(tab: .progress)
                }
                MenuBarButton(icon: "photo.on.rectangle", label: "Similar", color: .orange) {
                    openApp(tab: .similar)
                }
                MenuBarButton(icon: "binoculars.fill", label: "Monitor", color: .indigo) {
                    openApp(tab: .dupMonitor)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            if let updated = monitor.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Open DiskDoom") {
                openApp(tab: nil)
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Quit DiskDoom")
        }
    }

    // MARK: - Helpers

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .yellow
        case "C": return .orange
        default: return .red
        }
    }

    /// Bring the main window up (opening it if closed) and optionally
    /// navigate. All engines are the SAME instances the window uses, so
    /// setting state here navigates the real UI.
    private func openApp(tab: AppState.SidebarTab?) {
        if NSApp.windows.first(where: { $0.canBecomeMain }) == nil {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
        if let tab { state.sidebarTab = tab }
    }
}

// MARK: - Stat pill

private struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Menu bar action button

private struct MenuBarButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isHovered ? .white : color)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(isHovered ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isHovered ? color : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? Color.clear : Color.secondary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
