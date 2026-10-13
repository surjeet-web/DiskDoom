import Foundation
import Testing
@testable import DiskDoom

@Suite struct PrivacyForecastMeasurementTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let GB: Int64 = 1_000_000_000

    private func snapshot(daysAgo: Double, usedGB: Int64, totalGB: Int64 = 1_000,
                          breakdown: [String: Int64] = [:]) -> UsageSnapshot {
        UsageSnapshot(id: UUID(), timestamp: now.addingTimeInterval(-daysAgo * 86_400),
                      totalCapacity: totalGB * GB, usedSize: usedGB * GB,
                      freeSize: (totalGB - usedGB) * GB, categoryBreakdown: breakdown, source: .scan,
                      measurementSource: StorageCapacityReader.source)
    }

    @Test @MainActor func privacyStartsUnmeasuredAndCancellationDoesNotScore() {
        let engine = PrivacyScannerEngine()
        #expect(engine.score == nil)
        #expect(engine.scanMeasurement.statusLabel == "Not measured")
        engine.scan()
        #expect(engine.score == nil)
        engine.cancel()
        #expect(engine.score == nil)
        #expect(engine.scanMeasurement.reason?.contains("cancelled") == true)
    }

    @Test func completedScopedZeroFindingsIsRealZeroEvidence() {
        let result = PrivacyScanResult(findings: [], locationsExamined: 0, unreadable: 0,
                                       incompleteReason: nil, completedAt: now)
        #expect(result.scoreMeasurement.availableValue == 100)
        #expect(result.scoreMeasurement.source?.contains("heuristic") == true)
        #expect(result.scoreMeasurement.measuredAt == now)
    }

    @Test func privacyPartialAndPermissionDenialNeverScore100() {
        let partial = PrivacyScanResult(findings: [], locationsExamined: 0, unreadable: 0,
                                        incompleteReason: "Entry budget reached", completedAt: now)
        let denied = PrivacyScanResult(findings: [], locationsExamined: 0, unreadable: 4,
                                       incompleteReason: nil, completedAt: now)
        #expect(partial.scoreMeasurement.availableValue == nil)
        #expect(denied.scoreMeasurement.availableValue == nil)
        #expect(partial.scoreMeasurement.statusLabel == "Unavailable")
        #expect(denied.scoreMeasurement.statusLabel == "Unavailable")
    }

    @Test func privacyErrorAndStaleCannotBecomeAvailable() {
        let failed = PrivacyScanResult(findings: [], locationsExamined: 0, unreadable: 1,
                                       incompleteReason: nil, completedAt: now, failureReason: "I/O error")
        #expect(failed.scoreMeasurement.statusLabel == "Measurement failed")
        #expect(failed.scoreMeasurement.availableValue == nil)
        let completed = PrivacyScanResult(findings: [], locationsExamined: 0, unreadable: 0,
                                          incompleteReason: nil, completedAt: now)
        let stale = completed.scoreMeasurement.applyingFreshness(maxAge: PrivacyScannerEngine.freshnessTTL,
                                                                 now: now.addingTimeInterval(3_601))
        #expect(stale.statusLabel == "Stale")
        #expect(stale.availableValue == nil)
        #expect(stale.recordedValue == 100)
    }

    @Test func emptyAndShortHistoryDoNotEstablishSafety() {
        let empty = DiskForecastEngine.computeForecast(from: [], now: now)
        #expect(empty.riskEvidence(now: now) == .insufficient)
        let short = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 1, usedGB: 100),
                                                               snapshot(daysAgo: 0, usedGB: 101)], now: now)
        #expect(short.daysUntilFull == nil)
        #expect(short.riskEvidence(now: now) == .insufficient)
    }

    @Test func growingLongHorizonIsUnknownNotSafeOrShrinking() {
        let forecast = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 8, usedGB: 100, totalGB: 2_000),
            snapshot(daysAgo: 4, usedGB: 101, totalGB: 2_000), snapshot(daysAgo: 0, usedGB: 102, totalGB: 2_000)], now: now)
        #expect(forecast.hasReliableProjection)
        #expect(forecast.trendDirection == .growing)
        #expect(forecast.daysUntilFull == nil)
        #expect(forecast.riskEvidence(now: now) == .growingHorizonUnknown)
    }

    @Test func reliableRealZeroGrowthHasNoFillRiskDetected() {
        let forecast = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 8, usedGB: 100),
            snapshot(daysAgo: 4, usedGB: 100), snapshot(daysAgo: 0, usedGB: 100)], now: now)
        #expect(forecast.dailyChangeBytes == 0)
        #expect(forecast.riskEvidence(now: now) == .noRiskDetected)
    }

    @Test func oldCloselySpacedSamplesDoNotGainConfidenceWithAge() {
        let forecast = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 10, usedGB: 100),
            snapshot(daysAgo: 9.9, usedGB: 110), snapshot(daysAgo: 9.8, usedGB: 120)], now: now)
        #expect(!forecast.hasReliableProjection)
        #expect(forecast.daysUntilFull == nil)
        #expect(forecast.riskEvidence(now: now) == .stale)
    }

    @Test func previouslyReliableForecastExpires() {
        let forecast = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 8, usedGB: 100),
            snapshot(daysAgo: 4, usedGB: 200), snapshot(daysAgo: 0, usedGB: 300)], now: now)
        #expect(forecast.riskEvidence(now: now.addingTimeInterval(86_401)) == .stale)
    }

    @Test func subdayFillEstimateIsOneNotZeroOrNil() {
        let forecast = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 8, usedGB: 100),
            snapshot(daysAgo: 4, usedGB: 500), snapshot(daysAgo: 0, usedGB: 980)], now: now)
        #expect(forecast.daysUntilFull == 1)
        #expect(forecast.riskEvidence(now: now) == .estimatedFull(days: 1))
        #expect(DiskForecast.RiskEvidence.estimatedFull(days: 1).label.contains("or less"))
    }

    @Test func criticalDateIsTenPercentFreeNotFullDate() throws {
        let forecast = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 8, usedGB: 300),
            snapshot(daysAgo: 4, usedGB: 400), snapshot(daysAgo: 0, usedGB: 500)], now: now)
        let critical = try #require(forecast.criticalDate)
        #expect(abs(critical.timeIntervalSince(now) / 86_400 - 16) < 0.01)
        #expect(forecast.daysUntilFull == 20)
    }

    @Test func categoryGrowthNeverTreatsMissingKeyAsZero() {
        let forecast = DiskForecastEngine.computeForecast(from: [
            snapshot(daysAgo: 8, usedGB: 100, breakdown: ["caches": 0, "oldOnly": GB]),
            snapshot(daysAgo: 4, usedGB: 150),
            snapshot(daysAgo: 0, usedGB: 200, breakdown: ["caches": GB, "newOnly": GB])], now: now)
        #expect(forecast.categoryGrowth.count == 1)
        #expect(forecast.categoryGrowth.first?.category == "caches")
        #expect(forecast.categoryGrowth.first?.previousSize == 0)
        #expect(forecast.categoryGrowth.first?.changeBytes == GB)
        let missing = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 8, usedGB: 100),
            snapshot(daysAgo: 4, usedGB: 150), snapshot(daysAgo: 0, usedGB: 200, breakdown: ["caches": GB])], now: now)
        #expect(missing.categoryGrowth.isEmpty)
    }

    @Test func invalidCapacitiesCannotEstablishProjection() {
        let invalid = UsageSnapshot(id: UUID(), timestamp: now, totalCapacity: 100,
                                    usedSize: 101, freeSize: -1, categoryBreakdown: [:], source: .scan,
                                    measurementSource: StorageCapacityReader.source)
        let result = DiskForecastEngine.computeForecast(from: [invalid, invalid, invalid], now: now)
        #expect(result.history.isEmpty)
        #expect(result.riskEvidence(now: now) == .insufficient)
    }

    @Test func realZeroFreeSpaceIsNotMissingEvidence() {
        let result = DiskForecastEngine.computeForecast(from: [snapshot(daysAgo: 0, usedGB: 1_000)], now: now)
        #expect(result.currentFree == 0)
        #expect(result.history.count == 1)
        #expect(result.riskEvidence(now: now) == .lowFreeSpace)
    }

    @Test func legacyJSONDecodesWithoutInventingMeasurementProvenance() throws {
        let encoded = try JSONEncoder().encode(snapshot(daysAgo: 0, usedGB: 1_000))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "measurementSource")
        let legacy = try JSONDecoder().decode(UsageSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.measurementSource == nil)
        #expect(!legacy.hasVerifiedCapacitySource)
        #expect(legacy.freeSize == 0)
        let result = DiskForecastEngine.computeForecast(from: [legacy, legacy, legacy], now: now)
        #expect(result.history.isEmpty)
        #expect(result.riskEvidence(now: now) == .insufficient)
        #expect(result.daysUntilFull == nil)
    }

    @Test func unknownCapacityAPIAndFutureMeasurementsAreExcluded() {
        let unknown = UsageSnapshot(id: UUID(), timestamp: now, totalCapacity: 1_000 * GB,
            usedSize: 1_000 * GB, freeSize: 0, categoryBreakdown: ["caches": GB], source: .scan,
            measurementSource: "volumeAvailableCapacityForImportantUsage")
        let future = snapshot(daysAgo: -1, usedGB: 1_000, breakdown: ["caches": GB])
        let verified = [snapshot(daysAgo: 8, usedGB: 100), snapshot(daysAgo: 4, usedGB: 100),
                        snapshot(daysAgo: 0, usedGB: 100)]
        let result = DiskForecastEngine.computeForecast(from: verified + [unknown, future], now: now)
        #expect(result.history.count == 3)
        #expect(result.currentFree == 900 * GB)
        #expect(result.dailyChangeBytes == 0)
        #expect(result.categoryGrowth.isEmpty)
        #expect(result.riskEvidence(now: now) == .noRiskDetected)
    }

    @Test @MainActor func computeDoesNotPublishFakeZeroCapacityForLegacyOrFutureHistory() async {
        let engine = DiskForecastEngine()
        let legacy = UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-86_400),
            totalCapacity: 1_000 * GB, usedSize: 1_000 * GB, freeSize: 0,
            categoryBreakdown: [:], source: .scan)
        let future = UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(86_400),
            totalCapacity: 1_000 * GB, usedSize: 1_000 * GB, freeSize: 0,
            categoryBreakdown: [:], source: .launch, measurementSource: StorageCapacityReader.source)
        engine.seedHistory([legacy, future])
        await engine.compute()
        #expect(engine.forecast == nil)
        #expect(engine.forecastMeasurement.availableValue == nil)
        #expect(engine.forecastMeasurement.reason?.contains("Legacy") == true)
        #expect(engine.history.map(\.id) == [legacy.id, future.id])
        #expect(!engine.alerts.contains { $0.title.contains("Disk full") || $0.title.contains("spike") })
    }

    @Test @MainActor func spikeAlertsUseOnlyVerifiedCompatibleHistory() async {
        let engine = DiskForecastEngine()
        let current = Date()
        let verified = [8.0, 4.0, 0.0].map { days in
            UsageSnapshot(id: UUID(), timestamp: current.addingTimeInterval(-days * 86_400),
                totalCapacity: 1_000 * GB, usedSize: 100 * GB, freeSize: 900 * GB,
                categoryBreakdown: [:], source: .launch, measurementSource: StorageCapacityReader.source)
        }
        let legacy = UsageSnapshot(id: UUID(), timestamp: current, totalCapacity: 1_000 * GB,
            usedSize: 1_000 * GB, freeSize: 0, categoryBreakdown: [:], source: .scan)
        engine.seedHistory(verified + [legacy])
        await engine.compute()
        #expect(engine.forecast?.history.count == 3)
        #expect(engine.forecast?.currentFree == 900 * GB)
        #expect(engine.history.count == 4)
        #expect(engine.alerts.isEmpty)
    }
}
