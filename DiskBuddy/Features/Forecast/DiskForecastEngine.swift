import Foundation

// MARK: - D2 Disk Space Forecast engine (linear regression on snapshots; Foundation only)

struct ForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let usedGB: Double
    let isPrediction: Bool
}

struct DiskForecast {
    let points: [ForecastPoint]
    let daysUntilFull: Int?
    let fillDate: Date?
    let dailyGrowthGB: Double
    let freeGB: Double
    let totalGB: Double
    let isFilling: Bool
}

final class DiskForecastEngine: ObservableObject {
    @Published private(set) var forecast: DiskForecast?

    func compute() {
        let snaps = MockSnapshots.initial.sorted { $0.date < $1.date }
        guard snaps.count >= 2 else { forecast = nil; return }

        // Real free/total capacity (no entitlement needed for volume capacity keys).
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForOpportunisticUsageKey, .volumeTotalCapacityKey])
        let freeGB = Double(values?.volumeAvailableCapacityForOpportunisticUsage ?? 490_000_000_000) / 1_073_741_824
        let totalGB = Double(values?.volumeTotalCapacity ?? 746_000_000_000) / 1_073_741_824
        let usedGB = totalGB - freeGB

        let t0 = snaps[0].date
        let data: [(Double, Double)] = snaps.map {
            ($0.date.timeIntervalSince(t0) / 86_400, Double($0.totalBytes) / 1_073_741_824)
        }
        let (slope, intercept) = Self.regression(data)

        var points: [ForecastPoint] = snaps.map {
            ForecastPoint(date: $0.date, usedGB: Double($0.totalBytes) / 1_073_741_824, isPrediction: false)
        }
        let now = Date()
        points.append(ForecastPoint(date: now, usedGB: usedGB, isPrediction: false))
        let nowOffset = now.timeIntervalSince(t0) / 86_400
        for day in stride(from: nowOffset + 1, through: nowOffset + 90, by: 1) {
            points.append(ForecastPoint(
                date: t0.addingTimeInterval(day * 86_400),
                usedGB: max(0, intercept + slope * day),
                isPrediction: true))
        }

        let daysUntilFull = slope > 0 ? max(0, Int(freeGB / slope)) : nil
        forecast = DiskForecast(
            points: points,
            daysUntilFull: daysUntilFull,
            fillDate: daysUntilFull.map { Calendar.current.date(byAdding: .day, value: $0, to: now) ?? now },
            dailyGrowthGB: slope,
            freeGB: freeGB,
            totalGB: totalGB,
            isFilling: slope > 0.1)
    }

    private static func regression(_ points: [(Double, Double)]) -> (Double, Double) {
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.0 }
        let sumY = points.reduce(0) { $0 + $1.1 }
        let sumXY = points.reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = points.reduce(0) { $0 + $1.0 * $1.0 }
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return (0, sumY / n) }
        let slope = (n * sumXY - sumX * sumY) / denom
        return (slope, (sumY - slope * sumX) / n)
    }
}
