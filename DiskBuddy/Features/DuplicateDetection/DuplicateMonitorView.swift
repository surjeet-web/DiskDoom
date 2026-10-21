import SwiftUI
import AppKit
import UserNotifications

// MARK: - Duplicate Monitor (watched folders + cleanup reminders)

struct DuplicateMonitorView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var monitor: DuplicateMonitor

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Space.l) {
                    summaryCards
                    scheduleCard
                    foldersCard
                    reminderCard
                }
                .padding(DesignTokens.Space.l)
            }
        }
        .task { monitor.start() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Image(systemName: "binoculars.fill")
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background { MetalSurface(depth: 2, accent: DesignTokens.Palette.violet) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicate Monitor").font(.title2.weight(.semibold))
                Text("Watch folders for new duplicates and remind you to clean up.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await monitor.checkNow() }
            } label: {
                Label(monitor.isChecking ? "Checking…" : "Check Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PlateButtonStyle(primary: true))
            .disabled(monitor.isChecking || monitor.folders.isEmpty)
        }
        .padding(24)
        .background { MetalSurface(family: .canopy, flatSide: .top, accent: DesignTokens.Palette.violet) }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: DesignTokens.Space.m)], spacing: DesignTokens.Space.m) {
            statCard("Watched folders", "\(monitor.folders.count)", "folder.fill", DesignTokens.Palette.cyan)
            statCard("Known sets", "\(monitor.lastTotalSets)", "doc.on.doc.fill", DesignTokens.Palette.violet)
            statCard("New last check", "\(monitor.lastNewSets)", "sparkles", DesignTokens.Palette.orange)
            statCard("Potential", monitor.lastPotentialBytes.fileSizeString, "internaldrive", DesignTokens.Palette.teal)
        }
    }

    private func statCard(_ label: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .industrialPanel(.plate, flatSide: .bottom, accent: color)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            Text("Schedule").font(.headline)
            HStack {
                Picker("Check folders", selection: $monitor.interval) {
                    ForEach(DuplicateMonitorInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .frame(width: 200)
                Spacer()
                Text("Last check: \(monitor.lastCheckLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(monitor.statusMessage)
                .font(.caption)
                .foregroundStyle(monitor.lastNewSets > 0 ? .orange : .secondary)
            Text("The first check records a baseline. Later checks notify only about newly discovered duplicate sets.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .industrialPanel(.tiered, flatSide: .right, accent: DesignTokens.Palette.violet)
    }

    private var foldersCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            HStack {
                Text("Monitored Folders").font(.headline)
                Spacer()
                Button("Add Folder…", systemImage: "plus") { addFolders() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if monitor.folders.isEmpty {
                Text("No folders watched yet. Add Downloads, Desktop, or an external drive.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignTokens.Space.s)
            } else {
                ForEach(monitor.folders, id: \.self) { folder in
                    HStack(spacing: DesignTokens.Space.s) {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(folder)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Reveal", systemImage: "arrow.forward.circle") {
                            NSWorkspace.shared.selectFile(folder, inFileViewerRootedAtPath: "")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                        Button("Remove", systemImage: "minus.circle") {
                            monitor.removeFolder(folder)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Stop watching this folder")
                    }
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
        .industrialPanel(.well, flatSide: .right, accent: DesignTokens.Palette.cyan)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
            Text("Cleanup Reminder").font(.headline)
            HStack {
                Picker("Remind me", selection: $monitor.cleanupReminder) {
                    ForEach(CleanupReminderFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .frame(width: 200)
                Spacer()
                Button("Enable Notifications") {
                    state.permissions.requestNotifications()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("Reminders appear through macOS notifications. The reference app offers two weeks, three months, six months, and one year; DiskBuddy keeps the same idea with practical intervals.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .industrialPanel(.boot, flatSide: .bottom, accent: DesignTokens.Palette.orange)
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        if panel.runModal() == .OK {
            for url in panel.urls {
                monitor.addFolder(url.path)
            }
        }
    }
}

#Preview {
    DuplicateMonitorView()
        .environmentObject(AppState())
        .environmentObject(DuplicateMonitor())
        .frame(width: 900, height: 700)
}
