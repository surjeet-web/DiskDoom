import SwiftUI

// MARK: - D10 Live File Activity view

struct FileFeedView: View {
    @EnvironmentObject var monitor: FileFeedMonitor

    private var watchedList: String {
        monitor.watchPaths
            .map { ($0 as NSString).lastPathComponent }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live File Activity").font(.title2.weight(.semibold))
                    HStack(spacing: DesignTokens.Space.s) {
                        Circle()
                            .fill(monitor.isMonitoring ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(monitor.isMonitoring ? "Monitoring \(monitor.watchPaths.count) folders" : "Paused")
                        Text("· \(monitor.eventsPerMinute) events/min")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Watching: \(watchedList)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button(monitor.isMonitoring ? "Pause" : "Start") {
                    monitor.isMonitoring ? monitor.stop() : monitor.start()
                }
                .buttonStyle(.bordered)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            if monitor.events.isEmpty {
                EmptyState(symbol: "antenna.radiowaves.left.and.right", title: "No file activity yet", message: "Start monitoring to see live file creation attributed to the app that created it.")
            } else {
                List {
                    ForEach(monitor.events) { event in
                        HStack(spacing: DesignTokens.Space.m) {
                            Image(systemName: event.isCreated ? "doc.badge.plus" : "doc.badge.gearshape")
                                .foregroundStyle(event.isCreated ? .green : .orange)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: DesignTokens.Space.s) {
                                    Text(event.fileName).font(.callout.weight(.medium))
                                    if let app = event.attributedApp {
                                        Text("← \(app)")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(event.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(event.date, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            if !monitor.isMonitoring { monitor.start() } // live the moment you open the tab
        }
        .onDisappear { monitor.stop() }
    }
}

#Preview {
    FileFeedView()
        .environmentObject(FileFeedMonitor())
        .frame(width: 700, height: 500)
}
