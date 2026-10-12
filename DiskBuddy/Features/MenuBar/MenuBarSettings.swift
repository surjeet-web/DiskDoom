import SwiftUI
import UserNotifications

// MARK: - Feature 6: Menu Bar settings (style, thresholds, notifications)

struct MenuBarSettingsTab: View {
    @EnvironmentObject var monitor: MenuBarMonitor
    @AppStorage("menuBarStyle") private var menuBarStyle = "iconAndText"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("weeklyDigestEnabled") private var weeklyDigestEnabled = false
    @AppStorage("lowSpaceAlerts") private var lowSpaceAlerts = true
    @AppStorage("warningThreshold") private var warningThreshold = 15.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 5.0
    @State private var notificationPermission = false

    enum MenuBarStyle: String, CaseIterable {
        case iconOnly = "Icon Only"
        case textOnly = "Text Only"
        case iconAndText = "Icon + Text"
        case compact = "Compact"
    }

    var body: some View {
        Form {
            Section("Menu Bar Display") {
                Picker("Style", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style.rawValue)
                    }
                }
                HStack {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    menuBarPreview
                }
                .padding(.vertical, 4)
                Text("The menu bar item shows live free space, colored by disk state. Click it for the full panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Space Alerts") {
                Toggle("Low disk space alerts", isOn: $lowSpaceAlerts)
                Toggle("Notifications enabled", isOn: $notificationsEnabled)
                HStack {
                    Text("Warning threshold")
                    Spacer()
                    Slider(value: $warningThreshold, in: 5...30, step: 5)
                        .frame(width: 120)
                    Text("\(Int(warningThreshold))% free")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 55)
                }
                HStack {
                    Text("Critical threshold")
                    Spacer()
                    Slider(value: $criticalThreshold, in: 1...10, step: 1)
                        .frame(width: 120)
                    Text("\(Int(criticalThreshold))% free")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 55)
                }
                HStack {
                    Image(systemName: notificationPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(notificationPermission ? .green : .red)
                    Text(notificationPermission
                         ? "Notifications enabled"
                         : "Notifications denied — enable in System Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !notificationPermission {
                        Spacer()
                        Button("Request Permission") {
                            Task {
                                _ = await requestPermission()
                                await refreshPermission()
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section("Weekly Digest") {
                Toggle("Weekly digest (Monday 9 AM)", isOn: $weeklyDigestEnabled)
                    .onChange(of: weeklyDigestEnabled) { enabled in
                        if enabled {
                            Task {
                                if await requestPermission() {
                                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                                        if settings.authorizationStatus == .authorized {
                                            NotificationService.shared.scheduleWeeklyDigest()
                                        }
                                    }
                                }
                            }
                        } else {
                            NotificationService.shared.cancelWeeklyDigest()
                        }
                    }
                Text("A weekly reminder to check your storage summary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Current Status") {
                LabeledContent("Free Space", value: ByteFormatting.format(monitor.freeSpace))
                LabeledContent("Used Space", value: ByteFormatting.format(monitor.usedSpace))
                LabeledContent("Total Capacity", value: ByteFormatting.format(monitor.totalCapacity))
                LabeledContent("Disk State", value: stateLabel)
                if let updated = monitor.lastUpdated {
                    LabeledContent("Last Poll", value: updated.formatted(date: .omitted, time: .standard))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await refreshPermission() }
    }

    private var stateLabel: String {
        switch monitor.spaceState {
        case .unknown: return "Unknown"
        case .healthy: return "Healthy"
        case .okay: return "Okay"
        case .low: return "Low"
        case .critical: return "Critical"
        case .full: return "Almost full"
        }
    }

    @ViewBuilder
    private var menuBarPreview: some View {
        HStack(spacing: 4) {
            switch menuBarStyle {
            case MenuBarStyle.iconOnly.rawValue:
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.green)
            case MenuBarStyle.textOnly.rawValue:
                Text(monitor.menuBarTitle == "—" ? "45G" : monitor.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            case MenuBarStyle.compact.rawValue:
                Text(monitor.menuBarTitle == "—" ? "45G" : monitor.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            default:
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                Text(monitor.menuBarTitle == "—" ? "45G" : monitor.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
    }

    private func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermission = settings.authorizationStatus == .authorized
    }
}
