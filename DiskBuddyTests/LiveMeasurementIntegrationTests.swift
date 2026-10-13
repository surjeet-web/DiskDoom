import Foundation
@preconcurrency import Darwin
import Testing
@testable import DiskDoom

/// Read-only hardware checks. These do not constitute visual/UI sign-off.
struct LiveMeasurementIntegrationTests {
    @Test func liveCapacityAgreesWithIndependentFilesystemAccounting() throws {
        let measurement = StorageCapacityReader.read()
        let capacity = try #require(measurement.availableValue)
        var filesystem = statfs()
        #expect(statfs("/", &filesystem) == 0)
        let blockSize = Int64(filesystem.f_bsize)
        let total = Int64(filesystem.f_blocks) * blockSize
        let free = Int64(filesystem.f_bavail) * blockSize
        #expect(capacity.totalBytes == total)
        // The two reads are not atomic: other applications may write between them.
        #expect(abs(capacity.freeBytes - free) < 1_073_741_824)
        #expect(measurement.measuredAt != nil)
        #expect(measurement.source == StorageCapacityReader.source)
    }

    @Test @MainActor func cpuRequiresARealDeltaAndPublishesTimestampedEvidence() async throws {
        let monitor = SystemMonitor()
        #expect(monitor.cpuMeasurement == .notMeasured)
        monitor.start()
        defer { monitor.stop() }
        let deadline = Date().addingTimeInterval(5)
        while monitor.cpuMeasurement.availableValue == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let percent = try #require(monitor.cpuMeasurement.availableValue)
        #expect(percent >= 0 && percent <= 100)
        let measuredAt = try #require(monitor.cpuMeasurement.measuredAt)
        #expect(Date().timeIntervalSince(measuredAt) < 5)
        #expect(monitor.cpuMeasurement.source != nil)
    }
}
