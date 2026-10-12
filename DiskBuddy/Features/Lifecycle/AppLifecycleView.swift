import SwiftUI
import AppKit

// MARK: - D5 App Lifecycle view

struct AppLifecycleView: View {
    @EnvironmentObject var engine: AppLifecycleEngine
    @EnvironmentObject var state: AppState
    @EnvironmentObject var inventory: AppInventoryService
    @State private var filter: AppLifecycleEntry.LifecycleStatus? = nil

    private var rows: [AppLifecycleEntry] {
        filter.map { f in engine.entries.filter { $0.status == f } } ?? engine.entries
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Lifecycle").font(.title2.weight(.semibold))
                    Text("How long since each installed app was last opened — recorded live when launches are observed. Abandoned apps (90+ days) are prime uninstall candidates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !engine.abandoned.isEmpty {
                        Text("\(engine.abandoned.count) abandoned apps · \(ByteFormatting.format(engine.abandonedBytes))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Picker("Status", selection: $filter) {
                    Text("All").tag(AppLifecycleEntry.LifecycleStatus?(nil))
                    ForEach(AppLifecycleEntry.LifecycleStatus.allCases, id: \.self) { s in
                        Text(s.label).tag(AppLifecycleEntry.LifecycleStatus?(s))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            List(rows) { entry in
                HStack(spacing: DesignTokens.Space.m) {
                    Circle()
                        .fill(statusColor(entry.status))
                        .frame(width: 10, height: 10)
                    Text(entry.appName).frame(width: 150, alignment: .leading).lineLimit(1)
                    Text(entry.status.label)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor(entry.status).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(entry.status))
                        .frame(width: 90, alignment: .leading)
                    Text(entry.lastLaunch.map(relativeDate) ?? "Never")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text("\(entry.launchCount)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                    Text(ByteFormatting.format(entry.bytes))
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Spacer()
                    // 90-day usage bar: marker at last-launch position.
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.08))
                            .overlay(alignment: .leading) {
                                if let days = entry.daysSinceLastLaunch, days < 90 {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor.opacity(0.5))
                                        .frame(width: max(4, geo.size.width * CGFloat(90 - days) / 90))
                                }
                            }
                    }
                    .frame(height: 14)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    if entry.status == .abandoned {
                        Button("Stage for Cleanup") {
                            state.stage(source: "Lifecycle", path: entry.path, bytes: entry.bytes)
                            state.showCleanup = true
                        }
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile((entry.path as NSString).expandingTildeInPath, inFileViewerRootedAtPath: "")
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .task(id: inventory.apps.count) {
            engine.compute(apps: inventory.apps)
            engine.startLaunchWatcher()
        }
        .onDisappear { engine.stopLaunchWatcher() }
    }

    private func statusColor(_ s: AppLifecycleEntry.LifecycleStatus) -> Color {
        switch s {
        case .active: return .green
        case .occasional: return .blue
        case .dormant: return .orange
        case .abandoned: return .red
        case .unknown: return .gray
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...29: return "\(days) days ago"
        default: return "\(days / 30) mo ago"
        }
    }
}

#Preview {
    AppLifecycleView()
        .environmentObject({ let e = AppLifecycleEngine(); e.compute(apps: []); return e }())
        .environmentObject(AppState())
        .environmentObject(AppInventoryService())
        .frame(width: 800, height: 500)
}
