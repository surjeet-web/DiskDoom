import Foundation
import Testing
@testable import DiskDoom

struct MeasurementContractTests {
    private let date = Date(timeIntervalSince1970: 1_000)

    @Test func missingCapacityIsUnavailableNotZero() {
        let result = StorageCapacityReader.fromReadings(totalBytes: 1_024, freeBytes: nil)
        #expect(result.availableValue == nil)
        #expect(result.recordedValue == nil)
        #expect(result.statusLabel == "Unavailable")
    }

    @Test func realZeroFreeIsAnAvailableFullDisk() throws {
        let result = StorageCapacityReader.fromReadings(totalBytes: 1_024, freeBytes: 0, measuredAt: date)
        let capacity = try #require(result.availableValue)
        #expect(capacity.freeBytes == 0)
        #expect(capacity.usedPercent == 100)
        #expect(result.measuredAt == date)
        #expect(result.source == StorageCapacityReader.source)
    }

    @Test func inconsistentCapacityIsAnErrorNotClamped() {
        for (total, free) in [(0, 0), (1_024, -1), (1_024, 2_048)] {
            let result = StorageCapacityReader.fromReadings(totalBytes: Int64(total), freeBytes: Int64(free))
            #expect(result.availableValue == nil)
            #expect(result.statusLabel == "Measurement failed")
        }
    }

    @Test func staleValueRetainsProvenanceButIsNotCurrent() {
        let result = Measurement.available(value: 0, measuredAt: date, source: "Recorded sample")
            .applyingFreshness(maxAge: 60, now: date.addingTimeInterval(61))
        #expect(result.availableValue == nil)
        #expect(result.recordedValue == 0)
        #expect(result.measuredAt == date)
        #expect(result.source == "Recorded sample")
        #expect(result.statusLabel == "Stale")
    }

    @Test func missingErrorAndUnmeasuredStatesCarryNoNumber() {
        let states: [DiskDoom.Measurement<Int>] = [.notMeasured, .unavailable(reason: "Denied"), .error(reason: "I/O failure")]
        for state in states {
            #expect(state.availableValue == nil)
            #expect(state.recordedValue == nil)
            #expect(state.measuredAt == nil)
        }
    }

    @Test func futureOrInvalidFreshnessCannotLookCurrent() {
        let result = Measurement.available(value: 5, measuredAt: date, source: "Sample")
        #expect(result.applyingFreshness(maxAge: 60, now: date.addingTimeInterval(-1)).availableValue == nil)
        #expect(result.applyingFreshness(maxAge: .nan, now: date).availableValue == nil)
    }

    @Test func permissionDenialIsUnavailable() {
        let errors = [NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
                      NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.Code.EACCES.rawValue))]
        for error in errors {
            let result = StorageCapacityReader.fromFailure(error)
            #expect(result.statusLabel == "Unavailable")
            #expect(result.availableValue == nil)
        }
    }

    @Test func ioFailureDoesNotBecomeAFullyUsedDisk() {
        let result = StorageCapacityReader.fromFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.Code.EIO.rawValue)))
        #expect(result.statusLabel == "Measurement failed")
        #expect(result.availableValue == nil)
    }

    @Test func invalidStoredCapacityIsRejected() {
        let data = Data(#"{"totalBytes":100,"freeBytes":200}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(StorageCapacity.self, from: data) }
    }

    @Test @MainActor func topologyAndSimulatorStartUnmeasured() {
        #expect(DiskTopologyService().currentCapacity == .notMeasured)
        let simulator = WhatIfSimulator()
        #expect(simulator.currentCapacity == .notMeasured)
        #expect(simulator.currentFree == nil)
        #expect(simulator.projectedFree == nil)
        #expect(simulator.currentFreePercent == nil)
    }

    @Test func overlappingTargetsCannotBeAddedAsUniqueSavings() {
        #expect(WhatIfSimulator.pathsOverlap(["/Users/test/Cache", "/Users/test/Cache/file"]))
        #expect(WhatIfSimulator.pathsOverlap(["/Users/test/Cache/file", "/Users/test/Cache"]))
        #expect(WhatIfSimulator.pathsOverlap(["/Users/test/file", "/Users/test/file"]))
        #expect(!WhatIfSimulator.pathsOverlap(["/Users/test/Cache", "/Users/test/CacheBackup/file"]))
    }
}
