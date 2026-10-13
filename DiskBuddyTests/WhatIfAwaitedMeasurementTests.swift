import Foundation
import XCTest
@testable import DiskDoom

final class WhatIfAwaitedMeasurementTests: XCTestCase {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/diskbuddy-whatif-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 123).write(to: directory.appendingPathComponent("fixture"))
        return directory
    }

    @MainActor
    func testDirectoryMeasurementIsAwaitedBeforeSelectedCleanup() async throws {
        let state = AppState()
        try XCTSkipUnless(state.license.canClean, "Cleanup requires an active trial or license")
        let directory = try fixtureDirectory()
        // Only this uniquely named, test-created fixture may be removed.
        let trashFixture = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash").appendingPathComponent(directory.lastPathComponent)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: trashFixture)
        }
        let recommendation = SimItem(title: "Test folder", subtitle: "Fixture", savings: 123,
            source: .devCaches, risk: .safe, icon: "folder", color: .blue,
            stagePaths: [directory.path], directAction: nil, manualNote: nil)
        let simulator = WhatIfSimulator(items: [recommendation])
        simulator.selectedIDs = [recommendation.id]
        let report = await simulator.executeSelected(state: state)
        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(report.totalFreed, 123)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(simulator.items.isEmpty)
        XCTAssertFalse(simulator.isExecuting)
    }

    @MainActor
    func testAwaitedIdentityRejectsRemovedAndRestagedDirectory() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState()
        XCTAssertTrue(state.stage(source: "Original", path: directory.path))
        let original = try XCTUnwrap(state.cleanupItems.first)
        XCTAssertEqual(original.sizeState, .measuring)
        state.cleanupItems.removeAll()
        XCTAssertTrue(state.stage(source: "Replacement", path: directory.path))
        let accepted = await state.awaitCleanupMeasurements(for: [original.path: original.id])
        XCTAssertTrue(accepted.isEmpty)
        XCTAssertNotEqual(state.cleanupItems.first?.id, original.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        state.cleanupItems.removeAll()
    }

    @MainActor
    func testAwaitHelperCompletesRealDirectoryMeasurementWithoutTrashing() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState()
        XCTAssertTrue(state.stage(source: "Test", path: directory.path))
        let item = try XCTUnwrap(state.cleanupItems.first)
        XCTAssertEqual(item.sizeState, .measuring)
        let accepted = await state.awaitCleanupMeasurements(for: [item.path: item.id])
        XCTAssertEqual(accepted, [directory.path])
        XCTAssertEqual(state.cleanupItems.first?.sizeState, .measured)
        XCTAssertEqual(state.cleanupItems.first?.bytes, 123)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        state.cleanupItems.removeAll()
    }

    @MainActor
    func testRefusedRecommendationRemainsSelectedForRetry() async throws {
        let state = AppState()
        let recommendation = SimItem(title: "Protected", subtitle: "Fixture", savings: 123,
            source: .devCaches, risk: .safe, icon: "folder", color: .blue,
            stagePaths: ["/System"], directAction: nil, manualNote: nil)
        let simulator = WhatIfSimulator(items: [recommendation])
        simulator.selectedIDs = [recommendation.id]
        let report = await simulator.executeSelected(state: state)
        XCTAssertEqual(report.succeeded, 0)
        XCTAssertEqual(simulator.items.map(\.id), [recommendation.id])
        XCTAssertTrue(simulator.selectedIDs.contains(recommendation.id))
    }
}
