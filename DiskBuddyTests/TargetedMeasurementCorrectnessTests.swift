import Foundation
import Testing
@testable import DiskDoom

struct ActualCPUSampleTests {
    private let date = Date(timeIntervalSince1970: 1_000)

    @Test func firstDeltaIsNotMeasuredAndReadFailureIsUnavailable() {
        var sampler = SystemMonitor.ProcessCPUSampler()
        let baseline = sampler.sample(pid: 1, ticks: 10, time: 1, launchDate: nil)
        #expect(baseline == nil)
        #expect(SystemMonitor.processCPUMeasurement(percent: baseline, readSucceeded: true, measuredAt: date) == .notMeasured)
        let failed = sampler.sample(pid: 1, ticks: nil, time: 2, launchDate: nil)
        let evidence = SystemMonitor.processCPUMeasurement(percent: failed, readSucceeded: false, measuredAt: date)
        #expect(evidence.availableValue == nil)
        #expect(evidence.statusLabel == "Unavailable")
        #expect(sampler.sample(pid: 1, ticks: 20, time: 3, launchDate: nil) == nil)
    }

    @Test func genuineIdleIsMeasuredZero() {
        var sampler = SystemMonitor.ProcessCPUSampler()
        _ = sampler.sample(pid: 1, ticks: 10, time: 1, launchDate: nil)
        let idle = sampler.sample(pid: 1, ticks: 10, time: 2, launchDate: nil)
        #expect(idle == 0)
        #expect(SystemMonitor.processCPUMeasurement(percent: idle, readSucceeded: true, measuredAt: date).availableValue == 0)
    }

    @Test func hostRequiresTwoActualCounterReads() {
        var sampler = SystemMonitor.CPUTickSampler()
        #expect(sampler.sample([.init(user: 5, idle: 5)]) == nil)
        #expect(sampler.sample([.init(user: 10, idle: 10)]) == 50)
    }

    @Test func chartsIgnoreMissingStaleAndFailedSamplesWithoutPadding() {
        var history = MonitorSampleHistory()
        #expect(history.samples.isEmpty)
        history.append(.notMeasured)
        history.append(.unavailable(reason: "Denied"))
        history.append(.error(reason: "Read failed"))
        history.append(.stale(value: 1, measuredAt: date, source: "cache"))
        #expect(history.samples.isEmpty)
        history.append(.available(value: 0, measuredAt: date, source: "CPU"))
        history.append(.available(value: 0, measuredAt: date, source: "CPU"))
        history.append(.available(value: 0.5, measuredAt: date.addingTimeInterval(7), source: "CPU"))
        #expect(history.samples.count == 2)
        #expect(history.samples.map(\.value) == [0, 0.5])
        #expect(history.samples[1].measuredAt.timeIntervalSince(history.samples[0].measuredAt) == 7)
    }

    @Test func historyRetainsOnlyLatestActualSamples() {
        var history = MonitorSampleHistory()
        for i in 0..<75 {
            history.append(.available(value: Double(i), measuredAt: date.addingTimeInterval(Double(i)), source: "CPU"))
        }
        #expect(history.samples.count == 60)
        #expect(history.samples.first?.value == 15)
        #expect(history.samples.last?.value == 74)
    }
}

struct ExtensionAggregationRegressionTests {
    @Test func aggregatesEveryRecordOfSameExtensionIncludingZero() {
        let groups = ExtensionCloudAggregation.groups([
            .init(path: "/a.TXT", bytes: 4, isDirectory: false),
            .init(path: "/b.txt", bytes: 9, isDirectory: false),
            .init(path: "/c.txt", bytes: 0, isDirectory: false),
            .init(path: "/folder.txt", bytes: 100, isDirectory: true),
            .init(path: "/d.zero", bytes: 0, isDirectory: false),
            .init(path: "/e.zero", bytes: 0, isDirectory: false),
            .init(path: "/plain", bytes: 7, isDirectory: false),
        ])
        #expect(groups.first { $0.ext == ".txt" } == .init(ext: ".txt", bytes: 13, files: 3))
        #expect(groups.first { $0.ext == ".zero" } == .init(ext: ".zero", bytes: 0, files: 2))
        #expect(groups.first { $0.ext == "(no extension)" }?.bytes == 7)
    }

    @Test func bytesAndCountsSaturateWithoutOverflow() {
        let groups = ExtensionCloudAggregation.groups([
            .init(path: "/a.bin", bytes: .max, isDirectory: false),
            .init(path: "/b.bin", bytes: 5, isDirectory: false),
        ])
        #expect(groups.first?.bytes == .max)
        #expect(groups.first?.files == 2)
        #expect(ExtensionCloudAggregation.saturatingCount(.max, 1) == .max)
        #expect(ExtensionCloudAggregation.saturatingBytes(0, -5) == 0)
    }
}

private final class ExplorerMeasurementFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var denied = false
    private var failure = false
    private var partial = false
    let date = Date(timeIntervalSince1970: 10_000)

    var count: Int { lock.withLock { calls } }
    func setDenied(_ value: Bool) { lock.withLock { denied = value } }
    func setFailure(_ value: Bool) { lock.withLock { failure = value } }
    func setPartial(_ value: Bool) { lock.withLock { partial = value } }
    func canRead(_ path: String) -> Bool { lock.withLock { !denied } }
    func measure(_ path: String, _ hidden: Bool) throws -> FolderMeasurement {
        try lock.withLock {
            calls += 1
            if failure { throw ExplorerError.enumerationFailed(path, "Injected read failure") }
            return FolderMeasurement(path: path, totalSize: 0, totalFileCount: 0, totalFolderCount: 0,
                                     children: [], measuredAt: date, includesHidden: hidden,
                                     measurementVersion: FolderMeasurement.currentMeasurementVersion,
                                     unreadableFolderCount: partial ? 1 : 0)
        }
    }
    func engine() -> FolderMeasurementEngine {
        FolderMeasurementEngine(perform: { try self.measure($0, $1) }, canRead: { self.canRead($0) })
    }
}

struct ExplorerMeasurementCorrectnessTests {
    @Test func cacheHasRealTTLAndPreservesTimestampAndSource() async throws {
        let fixture = ExplorerMeasurementFixture()
        let engine = fixture.engine()
        let first = try await engine.measure(path: "/fixture", now: fixture.date)
        let cached = try await engine.measure(path: "/fixture", now: fixture.date.addingTimeInterval(60))
        #expect(fixture.count == 1)
        #expect(cached.measuredAt == first.measuredAt)
        #expect(cached.measurementSource.contains("Memory cache"))
        #expect(cached.evidence(now: fixture.date.addingTimeInterval(61)).availableValue == nil)
        #expect(cached.evidence(now: fixture.date.addingTimeInterval(61)).statusLabel == "Stale")
        _ = try await engine.measure(path: "/fixture", now: fixture.date.addingTimeInterval(61))
        #expect(fixture.count == 2)
    }

    @Test func partialResultsAreLowerBoundsAndNeverCached() async throws {
        let fixture = ExplorerMeasurementFixture()
        fixture.setPartial(true)
        let engine = fixture.engine()
        let result = try await engine.measure(path: "/fixture", now: fixture.date)
        #expect(result.isPartial)
        _ = try await engine.measure(path: "/fixture", now: fixture.date)
        #expect(fixture.count == 2)
    }

    @Test func permissionLossEvictsPreviouslyMeasuredCache() async throws {
        let fixture = ExplorerMeasurementFixture()
        let engine = fixture.engine()
        _ = try await engine.measure(path: "/fixture", now: fixture.date)
        fixture.setDenied(true)
        do {
            _ = try await engine.measure(path: "/fixture", now: fixture.date)
            Issue.record("Permission denied must not return cached measured zero")
        } catch {
            #expect(FolderExplorerEngine.failureEvidence(error).statusLabel == "Unavailable")
        }
        fixture.setDenied(false)
        _ = try await engine.measure(path: "/fixture", now: fixture.date)
        #expect(fixture.count == 2)
    }

    @Test func refreshErrorEvictsPriorCache() async throws {
        let fixture = ExplorerMeasurementFixture()
        let engine = fixture.engine()
        _ = try await engine.measure(path: "/fixture", now: fixture.date)
        fixture.setFailure(true)
        do {
            _ = try await engine.measure(path: "/fixture", forceRefresh: true, now: fixture.date)
            Issue.record("Expected refresh failure")
        } catch {
            #expect(FolderExplorerEngine.failureEvidence(error).statusLabel == "Measurement failed")
        }
        fixture.setFailure(false)
        _ = try await engine.measure(path: "/fixture", now: fixture.date)
        #expect(fixture.count == 3)
    }

    @Test @MainActor func failedRefreshClearsCurrentExplorerMetricsAfterSuccess() async {
        let fixture = ExplorerMeasurementFixture()
        let engine = FolderExplorerEngine(measurementEngine: fixture.engine())
        await engine.load(canonicalPath: "/fixture", pushHistory: false, forceRefresh: false)
        #expect(engine.measurement != nil)
        fixture.setFailure(true)
        await engine.load(canonicalPath: "/fixture", pushHistory: false, forceRefresh: true)
        #expect(engine.error != nil)
        #expect(engine.measurement == nil)
        #expect(engine.children.isEmpty)
        #expect(engine.measurementState.statusLabel == "Measurement failed")
    }

    @Test func cacheIsBoundedAndHiddenFlagRemainsIndependent() async throws {
        let fixture = ExplorerMeasurementFixture()
        let engine = fixture.engine()
        for i in 0...FolderMeasurementEngine.cacheLimit {
            _ = try await engine.measure(path: "/fixture/\(i)", now: fixture.date)
        }
        let count = fixture.count
        for i in 0...FolderMeasurementEngine.cacheLimit {
            _ = try await engine.measure(path: "/fixture/\(i)", now: fixture.date)
        }
        #expect(fixture.count > count)
        _ = try await engine.measure(path: "/hidden", includeHidden: false, now: fixture.date)
        let hidden = try await engine.measure(path: "/hidden", includeHidden: true, now: fixture.date)
        #expect(hidden.includesHidden)
    }

    @Test func metricsDistinguishMissingDeniedPartialStaleAndGenuineZero() {
        var node = FolderNode(path: "/fixture", name: "fixture", size: 0,
                              isDirectory: true, isPackage: false, isSymlink: false,
                              childCount: nil, fileCount: 0, modified: nil, fileExtension: nil,
                              percentageOfParent: 0)
        #expect(node.evidence(node.size).statusLabel == "Not measured")
        #expect(node.sizeDisplay == "Not measured")
        let now = Date()
        node.measuredAt = now
        #expect(node.evidence(node.size, now: now).availableValue == 0)
        #expect(node.evidence(node.childCount, now: now).statusLabel == "Not measured")
        #expect(node.evidence(node.modified, now: now).statusLabel == "Not measured")
        node.isPartial = true
        node.parentIsPartial = true
        #expect(node.sizeDisplay.contains("lower bound"))
        #expect(node.fileCountDisplay.contains("lower bound"))
        #expect(node.shareDisplay.contains("incomplete"))
        node.measuredAt = now.addingTimeInterval(-61)
        #expect(node.sizeDisplay.contains("Stale cached"))
        node.isUnreadable = true
        #expect(node.evidence(node.size, now: now).availableValue == nil)
        #expect(node.sizeDisplay == "Unknown (permission denied)")
        #expect(node.fileCountDisplay == "Unavailable")
    }

    @Test func missingPathAndEnumerationErrorsAreNotMeasuredZero() {
        for error in [ExplorerError.pathNotFound("/missing"), .enumerationFailed("/fixture", "I/O") ] {
            let evidence = FolderExplorerEngine.failureEvidence(error)
            #expect(evidence.availableValue == nil)
            #expect(evidence.recordedValue == nil)
            #expect(evidence.statusLabel == "Measurement failed")
        }
    }
}
