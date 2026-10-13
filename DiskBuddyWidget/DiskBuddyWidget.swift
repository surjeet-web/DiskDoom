import WidgetKit
import SwiftUI

// MARK: - Feature 11: DiskBuddy desktop widget (small / medium / large)
//
// Data flows one way: the main app writes a snapshot JSON into the shared
// App Group container after each scan (WidgetDataBridge on the app side);
// the widget reads it here and blends it with a live volume-capacity read
// (capacity keys need no entitlement). Falls back to placeholders — never
// fabricated numbers — when the app hasn't run yet.

// MARK: - Shared snapshot contract (mirrors app-side WidgetDataBridge.Snapshot)

struct WidgetSnapshot: Codable {
    var schemaVersion: Int?
    var capacity: Measurement<StorageCapacity>?
    var scanSource: String?
    var freeBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var healthGrade: String?
    var lastScanDate: Date?
    var daysUntilFull: Int?
    var topHogs: [Hog] = []
    var updatedAt: Date?

    struct Hog: Codable {
        var name: String
        var size: Int64
    }
}

enum SharedWidgetStore {
    static let groupID = "group.com.diskdoom"

    static func read() -> WidgetSnapshot? {
        if let url = containerURL(),
           let data = try? Data(contentsOf: url.appendingPathComponent("widget-data.json")),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return snapshot
        }
        if let defaults = UserDefaults(suiteName: groupID),
           let data = defaults.data(forKey: "widget-data"),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    /// Group container via entitlement; nil when unavailable (dev builds).
    static func containerURL() -> URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        let direct = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(groupID)", isDirectory: true)
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
    }

    /// Live volume capacity — readable from the sandboxed widget.
    static func liveCapacity(now: Date = Date()) -> Measurement<StorageCapacity> {
        StorageCapacityReader.read(measuredAt: now)
    }
}

// MARK: - Pure widget measurement policy
enum WidgetMeasurementPolicy {
    static let capacityTTL: TimeInterval = 300
    static let scanTTL: TimeInterval = 86_400

    static func capacity(live: Measurement<StorageCapacity>, cached: Measurement<StorageCapacity>?, now: Date) -> Measurement<StorageCapacity> {
        let current = live.applyingFreshness(maxAge: capacityTTL, now: now)
        if current.availableValue != nil { return current }
        guard let cached else { return current }
        guard let value = cached.recordedValue, let date = cached.measuredAt,
              let source = cached.source, !source.isEmpty,
              StorageCapacity(totalBytes: value.totalBytes, freeBytes: value.freeBytes) != nil else {
            return .unavailable(reason: "Cached capacity is invalid or has no provenance")
        }
        switch cached.applyingFreshness(maxAge: capacityTTL, now: now) {
        case .available:
            return .available(value: value, measuredAt: date, source: "Cached · \(source)")
        default:
            return .stale(value: value, measuredAt: date, source: "Cached · \(source)")
        }
    }

    static func scan(_ snapshot: WidgetSnapshot?, now: Date) -> Measurement<WidgetSnapshot> {
        guard let snapshot, snapshot.schemaVersion == 2,
              let date = snapshot.lastScanDate, let source = snapshot.scanSource, !source.isEmpty else {
            return .unavailable(reason: "No dated scan available")
        }
        return Measurement.available(value: snapshot, measuredAt: date, source: source)
            .applyingFreshness(maxAge: scanTTL, now: now)
    }
}
// MARK: - End pure widget measurement policy

// MARK: - Timeline

struct DiskDoomEntry: TimelineEntry {
    let date: Date
    let capacity: Measurement<StorageCapacity>
    let scan: Measurement<WidgetSnapshot>
    var healthGrade: String? { scan.availableValue?.healthGrade }
    var lastScanDate: Date? { scan.measuredAt }
    var daysUntilFull: Int? { scan.availableValue?.daysUntilFull }
    var topHogs: [WidgetSnapshot.Hog] { Array((scan.availableValue?.topHogs ?? []).prefix(3)) }
    var totalBytes: Int64 { capacity.availableValue?.totalBytes ?? 0 }
    var freeBytes: Int64 { capacity.availableValue?.freeBytes ?? 0 }

    var capacityLabel: String {
        guard let date = capacity.measuredAt else { return capacity.statusLabel }
        let label = capacity.source?.hasPrefix("Cached") == true ? "Cached · \(capacity.statusLabel)" : capacity.statusLabel
        return "\(label) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    func aged(at date: Date) -> Self {
        Self(date: date, capacity: capacity.applyingFreshness(maxAge: WidgetMeasurementPolicy.capacityTTL, now: date),
             scan: scan.applyingFreshness(maxAge: WidgetMeasurementPolicy.scanTTL, now: date))
    }
}

struct DiskDoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiskDoomEntry {
        DiskDoomEntry(date: Date(), capacity: .notMeasured, scan: .notMeasured)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiskDoomEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskDoomEntry>) -> Void) {
        let entry = current()
        let expirations = [entry.capacity.measuredAt.map { $0.addingTimeInterval(WidgetMeasurementPolicy.capacityTTL + 1) },
                           entry.scan.measuredAt.map { $0.addingTimeInterval(WidgetMeasurementPolicy.scanTTL + 1) }]
            .compactMap { $0 }.filter { $0 > entry.date }.sorted()
        // Expiry entries invalidate displayed evidence even if WidgetKit delays the next read.
        completion(Timeline(entries: [entry] + expirations.map { entry.aged(at: $0) },
                            policy: .after(entry.date.addingTimeInterval(300))))
    }

    private func current() -> DiskDoomEntry {
        let now = Date()
        let live = SharedWidgetStore.liveCapacity(now: now)
        let snapshot = SharedWidgetStore.read()
        return DiskDoomEntry(
            date: now,
            capacity: WidgetMeasurementPolicy.capacity(live: live, cached: snapshot?.schemaVersion == 2 ? snapshot?.capacity : nil, now: now),
            scan: WidgetMeasurementPolicy.scan(snapshot, now: now))
    }
}

// MARK: - Widget views

struct DiskDoomWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DiskDoomEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(entry: entry)
        case .systemLarge: LargeWidgetView(entry: entry)
        default: MediumWidgetView(entry: entry)
        }
    }
}

private func fmt(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    if gb >= 100 { return String(format: "%.0f GB", gb) }
    if gb >= 10 { return String(format: "%.0f GB", gb) }
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    return String(format: "%.0f MB", Double(bytes) / 1_000_000)
}

private func stateColor(freePercent: Double) -> Color {
    switch freePercent {
    case ..<5: return .red
    case ..<15: return .orange
    case ..<30: return .yellow
    default: return .green
    }
}

private struct GaugeRing: View {
    let freeBytes: Int64
    let totalBytes: Int64
    let lineWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        let usedPercent = totalBytes > 0 ? min(max(1 - Double(freeBytes) / Double(totalBytes), 0), 1) : 0
        let freePercent = (1 - usedPercent) * 100
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(usedPercent))
                .stroke(stateColor(freePercent: freePercent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(totalBytes > 0 ? fmt(freeBytes) : "—")
                    .font(.system(size: diameter / 5.2, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text(totalBytes > 0 ? "free" : "unavailable")
                    .font(.system(size: diameter / 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: Small: gauge + free space

private struct SmallWidgetView: View {
    let entry: DiskDoomEntry

    var body: some View {
        VStack(spacing: 6) {
            GaugeRing(freeBytes: entry.freeBytes, totalBytes: entry.totalBytes, lineWidth: 9, diameter: 96)
            Text(entry.totalBytes > 0 ? "of \(fmt(entry.totalBytes))" : "—")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(entry.capacityLabel).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Medium: gauge + health + free/used

private struct MediumWidgetView: View {
    let entry: DiskDoomEntry

    var body: some View {
        HStack(spacing: 14) {
            GaugeRing(freeBytes: entry.freeBytes, totalBytes: entry.totalBytes, lineWidth: 10, diameter: 84)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("DiskDoom")
                        .font(.headline)
                    if let grade = entry.healthGrade {
                        Text(grade)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(gradeColor(grade).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(gradeColor(grade))
                    }
                }
                statRow(label: "Used", value: entry.totalBytes > 0 ? fmt(max(0, entry.totalBytes - entry.freeBytes)) : "—")
                statRow(label: "Free", value: entry.totalBytes > 0 ? "\(fmt(entry.freeBytes)) (\(Int(Double(entry.freeBytes) / Double(max(entry.totalBytes, 1)) * 100))%)" : "—")
                Text(entry.capacityLabel).font(.caption2).foregroundStyle(.secondary)
                if let days = entry.daysUntilFull, days < 90 {
                    Label("Full in \(days)d", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(days < 30 ? .red : .orange)
                }
                if let last = entry.lastScanDate {
                    Label("Last scan · \(entry.scan.statusLabel) · \(RelativeDateWidget.string(from: last))", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium).monospacedDigit())
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .yellow
        case "C": return .orange
        default: return .red
        }
    }
}

private enum RelativeDateWidget {
    static func string(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: Large: gauge + health + hogs + forecast

private struct LargeWidgetView: View {
    let entry: DiskDoomEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                GaugeRing(freeBytes: entry.freeBytes, totalBytes: entry.totalBytes, lineWidth: 11, diameter: 92)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("DiskDoom").font(.headline)
                        if let grade = entry.healthGrade {
                            Text(grade)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(gradeColor(grade))
                            Text("health")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    statRow("Used", entry.totalBytes > 0 ? fmt(max(0, entry.totalBytes - entry.freeBytes)) : "—")
                    statRow("Free", entry.totalBytes > 0 ? fmt(entry.freeBytes) : "—")
                    statRow("Capacity", entry.totalBytes > 0 ? fmt(entry.totalBytes) : "—")
                    Text(entry.capacityLabel).font(.caption2).foregroundStyle(.secondary)
                    if let days = entry.daysUntilFull, days < 90 {
                        Label("Disk full in ~\(days) days", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(days < 30 ? .red : .orange)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            if entry.topHogs.isEmpty {
                Text(entry.scan.statusLabel == "Stale" ? "Scan data expired. Open DiskDoom to scan again." : "Top space hogs appear here after a scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Top Space Hogs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                let maxSize = entry.topHogs.map(\.size).max() ?? 1
                ForEach(Array(entry.topHogs.enumerated()), id: \.offset) { _, hog in
                    HStack(spacing: 8) {
                        Text(hog.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 120, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(0.8))
                                    .frame(width: max(geo.size.width * CGFloat(hog.size) / CGFloat(max(maxSize, 1)), 3))
                            }
                        }
                        .frame(height: 8)
                        Text(fmt(hog.size))
                            .font(.caption.monospacedDigit())
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let last = entry.lastScanDate {
                    Text("Last scan · \(entry.scan.statusLabel) · \(RelativeDateWidget.string(from: last))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("DiskDoom")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(value).font(.caption.weight(.medium).monospacedDigit())
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .yellow
        case "C": return .orange
        default: return .red
        }
    }
}

// MARK: - Widget registration

struct DiskDoomSpaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.diskdoom.space", provider: DiskDoomProvider()) { entry in
            DiskDoomWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor)
                }
        }
        .configurationDisplayName("DiskDoom")
        .description("Free space, disk health, and top space hogs at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct DiskDoomWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiskDoomSpaceWidget()
    }
}
