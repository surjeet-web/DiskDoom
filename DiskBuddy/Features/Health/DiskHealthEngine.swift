import Foundation

// MARK: - D11 Disk Health Score engine (real scan records + real app inventory)

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
    let unusedAppRatio: Int // raw percent of unused apps (tracked only)
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
    /// Below this many indexed files the sample is too small to score; we
    /// show "scan first" rather than inventing a grade.
    static let minimumRecordsForScore = 10_000
    @Published private(set) var score: DiskHealthScore?

    /// Real computation. Unused-app ratio counts only apps with tracked
    /// launch history (unknown ≠ unused).
    func compute(records: [ScannedRecord], apps: [AppEntry], unusedBundleIDs: Set<String> = []) {
        // A health grade is only meaningful with a real scan behind it. The
        // old guard accepted `apps` alone, so at launch — when `records` is
        // still empty because it streams in asynchronously — every component
        // scored 100 and the app displayed a confident "A / 100 — your disk is
        // in great shape!" on a Mac that had never been scanned. That grade
        // also propagated to the menu bar and the desktop widget.
        let indexedFiles = records.reduce(0) { $0 + ($1.isDirectory ? 0 : 1) }
        guard indexedFiles >= Self.minimumRecordsForScore else {
            score = nil
            return
        }
        var total: Int64 = 0
        var cache: Int64 = 0
        var logs: Int64 = 0
        var stale: Int64 = 0
        // Single pass — this used to filter the full record array four times.
        for record in records where !record.isDirectory {
            let (sum, overflow) = total.addingReportingOverflow(record.bytes)
            total = overflow ? Int64.max : sum
            switch record.category {
            case .caches:
                let (s, o) = cache.addingReportingOverflow(record.bytes); cache = o ? Int64.max : s
            case .logs:
                let (s, o) = logs.addingReportingOverflow(record.bytes); logs = o ? Int64.max : s
            case .stale:
                let (s, o) = stale.addingReportingOverflow(record.bytes); stale = o ? Int64.max : s
            default:
                break
            }
        }
        total = max(total, 1)
        let junk = cache + logs + stale
        let junkPercent = min(100, Int(Double(junk) / Double(total) * 100))
        let stalePercent = min(100, Int(Double(stale) / Double(total) * 100))
        let cacheGB = Double(cache) / 1_073_741_824
        let cacheBloat = min(100, Int(cacheGB * 2.0))
        let tracked = apps.filter { !$0.isStale }
        let unused = tracked.filter { unusedBundleIDs.contains($0.bundleID) }
        let unusedRatio = tracked.isEmpty ? 0 : min(100, unused.count * 100 / tracked.count)

        let junkScore = max(0, 100 - junkPercent * 2)
        let staleScore = max(0, 100 - stalePercent * 5)
        let cacheScore = max(0, 100 - cacheBloat)
        // Only weight the unused-apps component when launch history actually
        // exists. Otherwise it is structurally 100 and hands out 25 free
        // points for a quantity that was never measured.
        let hasLaunchHistory = !unusedBundleIDs.isEmpty
        let unusedScore = hasLaunchHistory ? max(0, 100 - unusedRatio * 2) : nil
        var weighted = junkScore * 30 + staleScore * 20 + cacheScore * 25
        var weightTotal = 30 + 20 + 25
        if let unusedScore {
            weighted += unusedScore * 25
            weightTotal += 25
        }
        let overall = weightTotal > 0 ? weighted / weightTotal : 0

        var improvements: [HealthImprovement] = []
        if cache > 5_368_709_120 {
            // "cache / 2" is a heuristic, not a measurement — label it so the
            // green "could free" figure isn't read as a promise.
            improvements.append(.init(
                action: "Clean caches (\(ByteFormatting.format(cache)) found)",
                potentialSaving: cache / 2, impact: .high))
        }
        if stale > 0 {
            improvements.append(.init(
                action: "Remove stale files from uninstalled apps",
                potentialSaving: stale, impact: .medium))
        }
        if hasLaunchHistory, !unused.isEmpty {
            let unusedBytes = unused.reduce(0) { $0 + $1.totalBytes }
            improvements.append(.init(
                action: "Review \(unused.count) tracked-unused apps (not opened in 90+ days)",
                potentialSaving: unusedBytes, impact: .medium))
        }
        if logs > 1_073_741_824 {
            improvements.append(.init(
                action: "Clear accumulated logs",
                potentialSaving: logs, impact: .low))
        }

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
