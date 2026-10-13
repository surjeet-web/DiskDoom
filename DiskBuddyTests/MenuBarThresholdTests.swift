import Testing
import Foundation
@testable import DiskDoom

struct MenuBarThresholdTests {
    @Test func preservesValidThresholds() {
        let thresholds = MenuBarMonitor.normalizedThresholds(warning: 15, critical: 5)
        #expect(thresholds.warning == 15)
        #expect(thresholds.critical == 5)
    }

    @Test func keepsCriticalBelowWarning() {
        let thresholds = MenuBarMonitor.normalizedThresholds(warning: 10, critical: 40)
        #expect(thresholds.critical <= thresholds.warning)
    }

    @Test func rejectsNonFiniteAndOutOfRangePreferences() {
        let invalid = MenuBarMonitor.normalizedThresholds(warning: .nan, critical: .infinity)
        #expect(invalid.warning == 15)
        #expect(invalid.critical == 5)
        let bounded = MenuBarMonitor.normalizedThresholds(warning: -20, critical: 200)
        #expect(bounded.warning == 2)
        #expect(bounded.critical == 2)
    }

    @Test func exhaustedBudgetIsNotAnEmptyFolder() {
        let measurement = MenuBarMonitor.directoryBytes(
            FileManager.default.temporaryDirectory,
            deadline: .distantPast, token: ScanCancellation())
        #expect(measurement.bytes == 0)
        #expect(measurement.isPartial)
    }

    @Test func includesHiddenFilesInMeasuredFolder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskbuddy-menubar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 0, count: 13).write(to: directory.appendingPathComponent(".hidden"))
        try Data(repeating: 0, count: 29).write(to: directory.appendingPathComponent("visible"))
        let measurement = MenuBarMonitor.directoryBytes(
            directory, deadline: Date().addingTimeInterval(10), token: ScanCancellation())
        #expect(measurement.bytes == 42)
        #expect(!measurement.isPartial)
    }

    @Test func cancelledMeasurementIsPartial() {
        let token = ScanCancellation()
        token.cancel()
        let measurement = MenuBarMonitor.directoryBytes(
            FileManager.default.temporaryDirectory,
            deadline: .distantFuture, token: token)
        #expect(measurement.isPartial)
        #expect(measurement.bytes == 0)
    }
}
