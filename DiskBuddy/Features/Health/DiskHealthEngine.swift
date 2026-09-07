import Foundation

// MARK: - D11 Disk Health Score engine (mock inputs; Foundation only)

struct HealthImprovement {
    let action: String
    let potentialSaving: Int64
    let impact: Impact
    enum Impact { case low, medium, high }
}

struct DiskHealthScore {
    let overall: Int // 0–100
    let junkPercent: Int // raw percent of cleanable bytes
    let stalePercent: Int // raw percent of stale bytes
    let cacheBloatScore: Int // 0–100 normalized (higher = worse)
    let unusedAppRatio: Int // raw percent of unused apps
    let recommendation: String
    let improvements: [HealthImprovement]

    var grade: String {
        switch overall {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }
}

// Main-confined in practice (driven from UI/main thread), hence Sendable.
final class DiskHealthEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var score: DiskHealthScore?

    /// Mock computation from prototype scan totals. Production version takes
    /// real scan results; "unused" comes from tracked launch history, not atime.
    func compute() {
        let total = Double(MockScanData.totalBytes)
        let cache = 38.0e9, logs = 2.3e9, stale = 4.2e9
        let junk = cache + logs + stale
        let junkPercent = min(100, Int(junk / total * 100))
        let stalePercent = min(100, Int(stale / total * 100))
        let cacheBloat = min(100, Int(38.0 * 2.0))
        let unusedRatio = 29 // mock: 2 of 7 tracked apps unused > 90 days

        let junkScore = max(0, 100 - junkPercent * 2)
        let staleScore = max(0, 100 - stalePercent * 5)
        let cacheScore = max(0, 100 - cacheBloat)
        let unusedScore = max(0, 100 - unusedRatio * 2)
        let overall = (junkScore * 30 + staleScore * 20 + cacheScore * 25 + unusedScore * 25) / 100

        let improvements = [
            HealthImprovement(action: "Clean caches older than 30 days", potentialSaving: 19_000_000_000, impact: .high),
            HealthImprovement(action: "Remove files from 2 uninstalled apps", potentialSaving: 600_000_000, impact: .medium),
            HealthImprovement(action: "Review 2 unused apps (not opened in 90+ days)", potentialSaving: 5_800_000_000, impact: .medium),
            HealthImprovement(action: "Clear accumulated logs", potentialSaving: 2_300_000_000, impact: .low),
        ]

        let recommendation: String
        switch overall {
        case 80...100: recommendation = "Your disk is in great shape!"
        case 60..<80: recommendation = "Some cleanup would help. Focus on caches and unused apps."
        default: recommendation = "Your disk needs attention. Significant space can be reclaimed."
        }
        score = DiskHealthScore(
            overall: overall, junkPercent: junkPercent, stalePercent: stalePercent,
            cacheBloatScore: cacheBloat, unusedAppRatio: unusedRatio,
            recommendation: recommendation, improvements: improvements)
    }
}
