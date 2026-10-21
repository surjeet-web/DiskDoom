import SwiftUI
import Combine

struct ActivityNotice: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let category: String
    let occurredAt: Date
    var read: Bool
}

/// Local-only event history. It stores notification summaries, never scan paths.
@MainActor
final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()
    @Published private(set) var notices: [ActivityNotice]
    private let defaults: UserDefaults
    private let key = "diskdoom.activity.v1"
    var unreadCount: Int { notices.filter { !$0.read }.count }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notices = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ActivityNotice].self, from: $0) } ?? []
    }

    func record(title: String, body: String, category: String, now: Date = Date()) {
        if let previous = notices.first, previous.title == title, previous.body == body,
           previous.category == category, now.timeIntervalSince(previous.occurredAt) < 5 { return }
        notices.insert(ActivityNotice(id: UUID(), title: title, body: body, category: category, occurredAt: now, read: false), at: 0)
        notices = Array(notices.prefix(200))
        save()
    }

    func markRead(_ id: UUID) {
        guard let index = notices.firstIndex(where: { $0.id == id }) else { return }
        notices[index].read = true
        save()
    }

    func markAllRead() {
        for index in notices.indices { notices[index].read = true }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notices) { defaults.set(data, forKey: key) }
    }
}

struct ActivityCenterView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var activity = ActivityCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activity & Jobs").font(.title2.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if state.scanPhase == .scanning {
                HStack(spacing: 16) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading) {
                        Text("Scan in progress").font(.headline)
                        Text("Total work is not known yet. Open the scan to see measured progress.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("View") { state.sidebarTab = .explore; dismiss() }
                    Button("Cancel Scan") { state.cancelScan() }
                }.industrialPanel(.canopy, flatSide: .bottom, accent: DesignTokens.Palette.orange)
            } else {
                Label("No active disk scan", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(activity.unreadCount) unread · latest 200 local events").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Mark all read") { activity.markAllRead() }.disabled(activity.unreadCount == 0)
            }
            if activity.notices.isEmpty {
                EmptyState(symbol: "bell", title: "No activity yet", message: "Scan and cleanup summaries appear here. OS notifications still require your permission and notification preferences.")
            } else {
                List(activity.notices) { notice in
                    Button {
                        activity.markRead(notice.id)
                        switch notice.category {
                        case NotificationService.categoryScan: state.sidebarTab = .explore
                        case NotificationService.categoryCleanup: state.showCleanup = true
                        case NotificationService.categoryGamification: state.sidebarTab = .progress
                        case NotificationService.categoryMonitor: state.sidebarTab = .dupMonitor
                        default: state.sidebarTab = .storage
                        }
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: notice.read ? "envelope.open" : "envelope.badge")
                                .foregroundStyle(DesignTokens.Palette.cyan)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(notice.title).font(.headline)
                                Text(notice.body).font(.callout).foregroundStyle(.secondary)
                                Text(notice.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }.listStyle(.plain)
            }
        }
        .padding(28).frame(width: 640, height: 600)
        .background(DesignTokens.Palette.app).preferredColorScheme(.dark)
    }
}
