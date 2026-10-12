import Foundation
import SwiftUI

// MARK: - Disk Forecast: usage history + trend projection
//
// Records volume usage snapshots (launch + every scan) into a persistent
// JSON history, then runs linear regression to project when the disk will
// fill. Category breakdowns from scans show what's growing. Never
// fabricates: no capacity read → no forecast.

// MARK: - Models

struct UsageSnapshot: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let totalCapacity: Int64
    let usedSize: Int64
    let freeSize: Int64
    let categoryBreakdown: [String: Int64]
    let source: Source

    var usedPercent: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedSize) / Double(totalCapacity) * 100
    }

    enum Source: String, Codable {
        case scan, launch
    }
}

struct ForecastAlert: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: Severity
    let actionTab: AppState.SidebarTab?

    enum Severity {
        case info, warning, critical

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }
}

struct CategoryGrowth: Identifiable {
    let id = UUID()
    let category: String
    let currentSize: Int64
    let previousSize: Int64
    let changeBytes: Int64
    let dailyRateBytes: Int64

    var currentFormatted: String { ByteFormatting.format(currentSize) }
    var changeFormatted: String { ByteFormatting.format(abs(changeBytes)) }
    var dailyRateFormatted: String { ByteFormatting.format(abs(dailyRateBytes)) + "/day" }
    var isGrowing: Bool { changeBytes > 0 }
}

struct DiskForecast {
    let computedAt: Date
    let currentUsed: Int64
    let currentFree: Int64
    let totalCapacity: Int64

    let dailyChangeBytes: Int64
    let weeklyChangeBytes: Int64
    let trendDirection: TrendDirection
    let daysUntilFull: Int?
    let criticalDate: Date?
    let warningDate: Date?
    let projectedUsage30Days: Int64
    let projectedUsage90Days: Int64
    /// False when the history is too short to extrapolate. The projections
    /// above are then meaningless and the UI must not present them.
    let hasReliableProjection: Bool

    let history: [UsageSnapshot]
    let points: [ForecastPoint]
    let categoryGrowth: [CategoryGrowth]
    let confidenceLevel: ConfidenceLevel
    let dataPointCount: Int

    var dailyChangeFormatted: String {
        (dailyChangeBytes >= 0 ? "+" : "-") + ByteFormatting.format(abs(dailyChangeBytes)) + "/day"
    }
    var weeklyChangeFormatted: String {
        (weeklyChangeBytes >= 0 ? "+" : "-") + ByteFormatting.format(abs(weeklyChangeBytes)) + "/week"
    }

    enum TrendDirection {
        case growing, stable, shrinking

        var icon: String {
            switch self {
            case .growing: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .shrinking: return "arrow.down.right"
            }
        }

        var color: Color {
            switch self {
            case .growing: return .red
            case .stable: return .green
            case .shrinking: return .blue
            }
        }

        var label: String {
            switch self {
            case .growing: return "Growing"
            case .stable: return "Stable"
            case .shrinking: return "Shrinking"
            }
        }
    }

    enum ConfidenceLevel {
        case high, medium, low, insufficient

        var label: String {
            switch self {
            case .high: return "High confidence"
            case .medium: return "Medium confidence"
            case .low: return "Low confidence"
            case .insufficient: return "Not enough data"
            }
        }

        var icon: String {
            switch self {
            case .high: return "checkmark.seal.fill"
            case .medium: return "checkmark.seal"
            case .low: return "exclamationmark.triangle"
            case .insufficient: return "questionmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .high: return .green
            case .medium: return .yellow
            case .low: return .orange
            case .insufficient: return .red
            }
        }
    }
}

struct ForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let usedBytes: Int64
    let isProjected: Bool
}

// MARK: - Engine

@MainActor
final class DiskForecastEngine: ObservableObject {
    @Published private(set) var forecast: DiskForecast?
    @Published private(set) var isComputing = false
    @Published private(set) var statusText = ""
    @Published private(set) var history: [UsageSnapshot] = []
    @Published private(set) var alerts: [ForecastAlert] = []

    /// Test hook: redirect history storage (atomic box so statics stay
    /// concurrency-safe under StrictConcurrency).
    nonisolated static var directoryOverride: URL? {
        get { DirectoryOverrideBox.value }
        set { DirectoryOverrideBox.value = newValue }
    }

    private final class DirectoryOverrideBox: @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) static var value: URL?
    }

    private let maxHistoryDays = 365
    private var saveTask: Task<Void, Never>?

    private nonisolated static var historyFile: URL {
        let base = directoryOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DiskBuddy", isDirectory: true)
        return base.appendingPathComponent("forecast-history.json")
    }

    init() {
        history = Self.loadHistory()
    }

    // MARK: - Record

    func recordSnapshot(
        totalCapacity: Int64,
        usedSize: Int64,
        freeSize: Int64,
        categoryBreakdown: [String: Int64] = [:],
        source: UsageSnapshot.Source
    ) {
        guard totalCapacity > 0 else { return }
        let snapshot = UsageSnapshot(
            id: UUID(), timestamp: Date(),
            totalCapacity: totalCapacity, usedSize: usedSize, freeSize: freeSize,
            categoryBreakdown: categoryBreakdown, source: source)

        // Replace entries within the same hour (launch + scan back-to-back).
        //
        // Never let a *poorer* snapshot overwrite a richer one. At every launch
        // with a cached scan, `restoreCachedScan` records a `.scan` snapshot
        // WITH a category breakdown, then the launch job records a `.launch`
        // snapshot WITHOUT one — destroying the breakdown, after which every
        // category appeared to grow by its entire size.
        if let last = history.last, Date().timeIntervalSince(last.timestamp) < 3_600 {
            let isRicher = !snapshot.categoryBreakdown.isEmpty
                && snapshot.categoryBreakdown.count >= last.categoryBreakdown.count
            if isRicher || last.categoryBreakdown.isEmpty {
                history[history.count - 1] = snapshot
            }
        } else {
            history.append(snapshot)
        }
        // Prune beyond a year.
        let cutoff = Date().addingTimeInterval(-Double(maxHistoryDays) * 86_400)
        history = history.filter { $0.timestamp > cutoff }
        scheduleSave()
    }

    // MARK: - Compute

    func compute() async {
        isComputing = true
        guard history.count >= 2 else {
            forecast = nil
            isComputing = false
            statusText = "Need at least 2 usage snapshots over different hours — currently \(history.count)"
            alerts = [ForecastAlert(
                title: "Not enough data",
                detail: "DiskDoom records usage at every launch and scan. Come back after a few days for trend analysis.",
                severity: .info, actionTab: nil)]
            return
        }

        let input = history
        let result = await Task.detached { Self.computeForecast(from: input) }.value

        var computedAlerts: [ForecastAlert] = []
        if let days = result.daysUntilFull, days <= 7 {
            computedAlerts.append(ForecastAlert(
                title: "Disk full in \(days) days",
                detail: "At the current rate (\(result.dailyChangeFormatted)) you'll run out of space on \(result.criticalDate?.formatted(date: .abbreviated, time: .omitted) ?? "soon"). Clean up now.",
                severity: .critical, actionTab: .simulator))
        } else if let days = result.daysUntilFull, days <= 30 {
            computedAlerts.append(ForecastAlert(
                title: "Disk full in ~\(days) days",
                detail: "Storage is growing \(result.dailyChangeFormatted). Consider cleaning caches or old files.",
                severity: .warning, actionTab: .simulator))
        }
        if let warning = result.warningDate,
           warning < Date().addingTimeInterval(14 * 86_400) {
            computedAlerts.append(ForecastAlert(
                title: "Approaching low storage",
                detail: "Free space will drop below 20% by \(warning.formatted(date: .abbreviated, time: .omitted)).",
                severity: .warning, actionTab: .simulator))
        }
        // Sudden spike: > 5 GB added between recent snapshots.
        if history.count >= 3 {
            let recent = Array(history.suffix(3))
            let changes = zip(recent, recent.dropFirst()).map { $1.usedSize - $0.usedSize }
            if let spike = changes.max(), spike > 5_000_000_000 {
                computedAlerts.append(ForecastAlert(
                    title: "Sudden usage spike",
                    detail: "\(ByteFormatting.format(spike)) added between recent snapshots. Something may be growing unexpectedly.",
                    severity: .warning, actionTab: .folders))
            }
        }

        forecast = result
        alerts = computedAlerts
        isComputing = false
        statusText = Self.statusText(for: result)
    }

    /// Test hook: replace history with seeded fixtures.
    func seedHistory(_ snapshots: [UsageSnapshot]) {
        history = snapshots
    }

    func clearHistory() {
        history = []
        forecast = nil
        alerts = []
        try? FileManager.default.removeItem(at: Self.historyFile)
    }

    // MARK: - Core computation (pure, detached)

    /// A fill-date projection needs at least this many days of history.
    /// Anything shorter is two measurements of the same afternoon, and
    /// extrapolating from it produced "0 days until full".
    nonisolated static let minimumDaySpanForProjection: Double = 7

    nonisolated private static func computeForecast(from raw: [UsageSnapshot]) -> DiskForecast {
        let now = Date()
        let sorted = raw.sorted { $0.timestamp < $1.timestamp }
        // Never force-unwrap: `seedHistory` and paging can both leave this empty.
        guard let latest = sorted.last, let oldest = sorted.first else {
            return DiskForecast(
                computedAt: now, currentUsed: 0, currentFree: 0, totalCapacity: 0,
                dailyChangeBytes: 0, weeklyChangeBytes: 0, trendDirection: .stable,
                daysUntilFull: nil, criticalDate: nil, warningDate: nil,
                projectedUsage30Days: 0, projectedUsage90Days: 0,
                hasReliableProjection: false,
                history: [], points: [], categoryGrowth: [],
                confidenceLevel: .insufficient, dataPointCount: 0)
        }

        // Regression on used bytes over time.
        let (slope, intercept) = regression(sorted) // bytes/second
        let safeSlope = slope.isFinite ? slope : 0
        let rawDaily = safeSlope * 86_400
        let dailyChange = rawDaily.isFinite && abs(rawDaily) < Double(Int64.max)
            ? Int64(rawDaily) : 0
        let weeklyChange = dailyChange * 7

        let trend: DiskForecast.TrendDirection
        if abs(dailyChange) < 10_000_000 { // < 10 MB/day = stable
            trend = .stable
        } else if dailyChange > 0 {
            trend = .growing
        } else {
            trend = .shrinking
        }

        // Confidence gate. Two snapshots taken minutes apart at a single
        // launch (one from cached-scan hydration, one from the launch job)
        // produced a slope of ~288 GB/day and the header rendered
        // "0 days until full" in 56pt red plus a "Disk full in 0 days" alert.
        // A fill date is only meaningful over a real span of days.
        let daySpan = now.timeIntervalSince(oldest.timestamp) / 86_400
        let hasReliableTrend = sorted.count >= 3 && daySpan >= Self.minimumDaySpanForProjection

        // Days until full (only when growing, and only with a reliable trend).
        var daysUntilFull: Int?
        if dailyChange > 0, hasReliableTrend {
            let days = Double(latest.freeSize) / Double(dailyChange)
            // Floor at 1: rounding a sub-day value produced the alarming and
            // meaningless "Disk full in 0 days".
            if days >= 1, days < 3_650 { daysUntilFull = Int(days.rounded()) }
        }

        // Threshold crossing dates (10% / 20% free).
        let criticalThreshold = Int64(Double(latest.totalCapacity) * 0.10)
        let warningThreshold = Int64(Double(latest.totalCapacity) * 0.20)
        var criticalDate: Date?
        var warningDate: Date?
        if dailyChange > 0, hasReliableTrend {
            let daysCritical = Double(max(0, latest.freeSize - criticalThreshold)) / Double(dailyChange)
            let daysWarning = Double(max(0, latest.freeSize - warningThreshold)) / Double(dailyChange)
            if daysCritical > 0, daysCritical < 3_650 {
                criticalDate = now.addingTimeInterval(daysCritical * 86_400)
            }
            if daysWarning > 0, daysWarning < 3_650 {
                warningDate = now.addingTimeInterval(daysWarning * 86_400)
            }
        }

        // Projections (clamped to capacity).
        let projectedFor: (TimeInterval) -> Int64 = { offset in
            let raw = intercept + safeSlope * (latest.timestamp.timeIntervalSince1970 + offset)
            guard raw.isFinite, raw < Double(Int64.max), raw > Double(Int64.min) else {
                return latest.totalCapacity
            }
            return max(0, min(Int64(raw), latest.totalCapacity))
        }
        // Without a reliable trend, don't draw a projection at all — a bogus
        // slope silently saturated to "100% used, +412 GB".
        let projected30 = hasReliableTrend ? projectedFor(30 * 86_400) : nil
        let projected90 = hasReliableTrend ? projectedFor(90 * 86_400) : nil

        // Chart points: last 30 historical + 30 days of daily projections.
        var points: [ForecastPoint] = sorted.suffix(30).map {
            ForecastPoint(date: $0.timestamp, usedBytes: $0.usedSize, isProjected: false)
        }
        if hasReliableTrend {
            for day in 1...30 {
                let future = latest.timestamp.addingTimeInterval(Double(day) * 86_400)
                let raw = intercept + safeSlope * future.timeIntervalSince1970
                let used = (raw.isFinite && raw < Double(Int64.max))
                    ? max(0, min(Int64(raw), latest.totalCapacity))
                    : latest.totalCapacity
                points.append(ForecastPoint(date: future, usedBytes: used, isProjected: true))
            }
        }

        // Category growth (oldest vs latest breakdowns).
        var categoryGrowth: [CategoryGrowth] = []
        if !latest.categoryBreakdown.isEmpty || !oldest.categoryBreakdown.isEmpty {
            // Compare breakdowns only across a real span; otherwise every
            // category shows its entire size as "growth".
            let span = latest.timestamp.timeIntervalSince(oldest.timestamp)
            guard span >= Self.minimumDaySpanForProjection * 86_400 else {
                return DiskForecast(
                    computedAt: now, currentUsed: latest.usedSize,
                    currentFree: latest.freeSize, totalCapacity: latest.totalCapacity,
                    dailyChangeBytes: dailyChange, weeklyChangeBytes: weeklyChange,
                    trendDirection: trend,
                    daysUntilFull: nil, criticalDate: nil, warningDate: nil,
                    projectedUsage30Days: latest.usedSize,
                    projectedUsage90Days: latest.usedSize,
                    hasReliableProjection: false,
                    history: sorted, points: points, categoryGrowth: [],
                    confidenceLevel: .insufficient, dataPointCount: sorted.count)
            }
            let days = span / 86_400
            for category in Set(latest.categoryBreakdown.keys).union(oldest.categoryBreakdown.keys) {
                let current = latest.categoryBreakdown[category] ?? 0
                let previous = oldest.categoryBreakdown[category] ?? 0
                categoryGrowth.append(CategoryGrowth(
                    category: category,
                    currentSize: current,
                    previousSize: previous,
                    changeBytes: current - previous,
                    dailyRateBytes: Int64(Double(current - previous) / days)))
            }
            categoryGrowth.sort { $0.changeBytes > $1.changeBytes }
        }

        // Confidence.
        let confidence: DiskForecast.ConfidenceLevel
        switch (sorted.count, daySpan) {
        case (10..., 7...): confidence = .high
        case (5..., 3...): confidence = .medium
        case (3..., _): confidence = .low
        default: confidence = .insufficient
        }

        return DiskForecast(
            computedAt: now,
            currentUsed: latest.usedSize,
            currentFree: latest.freeSize,
            totalCapacity: latest.totalCapacity,
            dailyChangeBytes: dailyChange,
            weeklyChangeBytes: weeklyChange,
            trendDirection: trend,
            daysUntilFull: daysUntilFull,
            criticalDate: criticalDate,
            warningDate: warningDate,
            projectedUsage30Days: projected30 ?? latest.usedSize,
            projectedUsage90Days: projected90 ?? latest.usedSize,
            hasReliableProjection: hasReliableTrend,
            history: sorted,
            points: points,
            categoryGrowth: categoryGrowth,
            confidenceLevel: confidence,
            dataPointCount: sorted.count)
    }

    nonisolated private static func regression(_ snapshots: [UsageSnapshot]) -> (slope: Double, intercept: Double) {
        let n = Double(snapshots.count)
        guard n >= 2 else { return (0, 0) }
        let xs = snapshots.map { $0.timestamp.timeIntervalSince1970 }
        let ys = snapshots.map { Double($0.usedSize) }
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 1e-10 else { return (0, sumY / n) }
        let slope = (n * sumXY - sumX * sumY) / denominator
        return (slope, (sumY - slope * sumX) / n)
    }

    nonisolated private static func statusText(for forecast: DiskForecast) -> String {
        switch forecast.trendDirection {
        case .growing:
            if let days = forecast.daysUntilFull {
                return "Growing \(forecast.dailyChangeFormatted) — full in ~\(days) days"
            }
            return "Growing \(forecast.dailyChangeFormatted)"
        case .stable:
            return "Stable — no significant change"
        case .shrinking:
            return "Shrinking \(forecast.dailyChangeFormatted) — usage decreasing"
        }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let toSave = history
        saveTask = Task.detached {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(toSave) {
                try? FileManager.default.createDirectory(
                    at: Self.historyFile.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try? data.write(to: Self.historyFile, options: .atomic)
            }
        }
    }

    nonisolated private static func loadHistory() -> [UsageSnapshot] {
        guard let data = try? Data(contentsOf: historyFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UsageSnapshot].self, from: data)) ?? []
    }
}
