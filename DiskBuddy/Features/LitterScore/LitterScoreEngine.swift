import Foundation

// MARK: - D1 App Litter Score engine (real app inventory + tracked launches)
//
// "Days since last launch" comes ONLY from NSWorkspace launch history tracked
// by AppLifecycleEngine — never file atime. Unknown history contributes a
// neutral frequency component and the UI shows "Unknown", not a fake number.

struct LitterScoreEntry: Identifiable {
    let id = UUID()
    let appName: String
    let bundleID: String
    let bundleBytes: Int64
    let artifactBytes: Int64
    let score: Int // 0–100 composite (higher = more litter)
    let artifactRatio: Double // raw ratio, e.g. 2.0x
    let avgCacheAgeDays: Int? // nil = unknown (not estimated from atime)
    let daysSinceLastLaunch: Int? // nil = untracked yet
    let logBytes: Int64
    let httpBytes: Int64
    let artifactPaths: [String]
    let explanation: String
    let recommendation: String?

    var scoreLabel: String {
        switch score {
        case 0..<30: return "Clean"
        case 30..<60: return "Moderate"
        case 60..<80: return "Messy"
        default: return "Litterbug"
        }
    }
}

// Main-confined in practice (driven from UI/main thread), hence Sendable.
final class LitterScoreEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var entries: [LitterScoreEntry] = []
    @Published private(set) var isComputing = false

    var averageScore: Int {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.score } / entries.count
    }

    var totalLitter: Int64 { entries.reduce(0) { $0 + $1.artifactBytes } }

    /// Scores real inventory apps. Launch history is optional (nil = untracked).
    func compute(apps: [AppEntry], launchDays: [String: Int] = [:]) {
        isComputing = true
        defer { isComputing = false }
        entries = apps
            .filter { !$0.isStale && $0.bundleBytes > 0 }
            .map { scoreApp($0, daysSinceLastLaunch: launchDays[$0.bundleID]) }
            .sorted { $0.score > $1.score }
    }

    private func scoreApp(_ app: AppEntry, daysSinceLastLaunch: Int?) -> LitterScoreEntry {
        let ratio = Double(app.artifactBytes) / Double(max(app.bundleBytes, 1))
        let ratioScore = min(100.0, ratio * 20.0)
        let logs = app.artifacts.filter { $0.kind == "Logs" }.reduce(0) { $0 + $1.bytes }
        let http = app.artifacts.filter { $0.kind == "HTTPStorages" }.reduce(0) { $0 + $1.bytes }
        let logScore = min(100.0, Double(logs) / 104_857_600.0 * 100.0)
        let httpScore = min(100.0, Double(http) / 2_097_152_000.0 * 100.0)
        // Unknown launch history → neutral 50 (documented, not faked).
        let frequencyScore = daysSinceLastLaunch.map { min(100, $0 * 2) } ?? 50
        // Without tracked cache ages, the age component is neutral too.
        let composite = ratioScore * 0.35 + logScore * 0.20 + httpScore * 0.20
            + Double(frequencyScore) * 0.25

        var parts: [String] = []
        if ratio > 2.0 { parts.append(String(format: "%.1fx more artifacts than app size", ratio)) }
        if logs > 100_000_000 { parts.append("\(ByteFormatting.format(logs)) of logs") }
        if http > 500_000_000 { parts.append("\(ByteFormatting.format(http)) of web storage") }
        if let days = daysSinceLastLaunch, days > 30 {
            parts.append("Not launched in \(days) days")
        } else if daysSinceLastLaunch == nil {
            parts.append("Launch history not tracked yet")
        }

        return LitterScoreEntry(
            appName: app.name,
            bundleID: app.bundleID,
            bundleBytes: app.bundleBytes,
            artifactBytes: app.artifactBytes,
            score: min(100, max(0, Int(composite))),
            artifactRatio: ratio,
            avgCacheAgeDays: nil,
            daysSinceLastLaunch: daysSinceLastLaunch,
            logBytes: logs,
            httpBytes: http,
            artifactPaths: app.artifacts.map(\.path),
            explanation: parts.isEmpty ? "Typical artifact levels for an app of this size." : parts.joined(separator: ". "),
            recommendation: app.artifactBytes > 100_000_000 ? "Clean \(ByteFormatting.format(app.artifactBytes)) of caches" : nil)
    }
}
