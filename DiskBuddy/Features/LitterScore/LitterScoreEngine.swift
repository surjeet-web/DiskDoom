import Foundation

// MARK: - D1 App Litter Score engine (mock data; Foundation only, no SwiftUI)

// Production note: "days since last launch" must come from NSWorkspace
// launch notifications tracked by the app itself — never from file
// atime, which is throttled/unreliable on APFS. The mock values below
// stand in for that tracked history.

struct LitterScoreEntry: Identifiable {
    let id = UUID()
    let appName: String
    let bundleID: String
    let bundleBytes: Int64
    let artifactBytes: Int64
    let score: Int // 0–100 composite (higher = more litter)
    let artifactRatio: Double // raw ratio, e.g. 2.0x
    let avgCacheAgeDays: Int // raw day count (NOT a normalized score)
    let cacheAgeScore: Int // 0–100 normalized component
    let daysSinceLastLaunch: Int // raw day count (NOT a normalized score)
    let logBytes: Int64
    let httpBytes: Int64
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

final class LitterScoreEngine: ObservableObject {
    @Published private(set) var entries: [LitterScoreEntry] = []
    @Published private(set) var isComputing = false

    var averageScore: Int {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.score } / entries.count
    }

    var totalLitter: Int64 { entries.reduce(0) { $0 + $1.artifactBytes } }

    /// Mock computation. Production version takes real InstalledApp models;
    /// per-app day counts come from tracked launch history (see note above).
    func compute() {
        isComputing = true
        defer { isComputing = false }
        let mock: [(AppEntry, Int, Int)] = MockApps.all.map { app in
            // (app, avgCacheAgeDays, daysSinceLastLaunch) — hand-specified mock history.
            switch app.name {
            case "Google Chrome": return (app, 47, 0)
            case "Spotify": return (app, 82, 1)
            case "Xcode": return (app, 12, 0)
            case "Slack": return (app, 30, 2)
            case "Figma": return (app, 21, 9)
            case "Old VPN Client": return (app, 400, 320)
            default: return (app, 200, 180)
            }
        }
        entries = mock.map { scoreApp($0, avgCacheAgeDays: $1, daysSinceLastLaunch: $2) }
            .sorted { $0.score > $1.score }
    }

    private func scoreApp(_ app: AppEntry, avgCacheAgeDays: Int, daysSinceLastLaunch: Int) -> LitterScoreEntry {
        let ratio = Double(app.artifactBytes) / Double(max(app.bundleBytes, 1))
        let ratioScore = min(100.0, ratio * 20.0)
        let cacheAgeScore = min(100, Int(Double(avgCacheAgeDays) * 1.5))
        let logScore = min(100.0, Double(app.artifactBytes) / 20.0 / 1_048_576.0)
        let httpScore = min(100.0, Double(app.artifactBytes) / 4.0 / 2_097_152.0)
        let frequencyScore = min(100, daysSinceLastLaunch * 2)
        let composite = ratioScore * 0.30 + Double(cacheAgeScore) * 0.20
            + logScore * 0.15 + httpScore * 0.15 + Double(frequencyScore) * 0.20

        var parts: [String] = []
        if ratio > 2.0 { parts.append(String(format: "%.1fx more artifacts than app size", ratio)) }
        if avgCacheAgeDays > 30 { parts.append("Caches average \(avgCacheAgeDays) days old") }
        if daysSinceLastLaunch > 30 { parts.append("Not launched in \(daysSinceLastLaunch) days") }

        return LitterScoreEntry(
            appName: app.name,
            bundleID: app.bundleID,
            bundleBytes: app.bundleBytes,
            artifactBytes: app.artifactBytes,
            score: min(100, max(0, Int(composite))),
            artifactRatio: ratio,
            avgCacheAgeDays: avgCacheAgeDays,
            cacheAgeScore: cacheAgeScore,
            daysSinceLastLaunch: daysSinceLastLaunch,
            logBytes: app.artifactBytes / 20,
            httpBytes: app.artifactBytes / 4,
            explanation: parts.isEmpty ? "Typical artifact levels for an app of this size." : parts.joined(separator: ". "),
            recommendation: app.artifactBytes > 100_000_000 ? "Clean \(ByteFormatting.format(app.artifactBytes)) of caches" : nil)
    }
}
