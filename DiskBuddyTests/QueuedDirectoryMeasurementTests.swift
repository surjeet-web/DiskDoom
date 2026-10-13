import Foundation
import Testing
@testable import DiskDoom

@Suite
struct QueuedDirectoryMeasurementTests {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/diskbuddy-queue-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test @MainActor func directoryStagesImmediatelyAsPendingThenPublishesMeasuredSize() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 123).write(to: directory.appendingPathComponent("file"))
        let state = AppState()
        #expect(state.stage(source: "Test", path: directory.path))
        #expect(state.cleanupItems.first?.sizeState == .measuring)
        #expect(state.cleanupSizeSummary.contains("measuring"))
        #expect(state.cleanupTotal == 0)
        let blocked = state.executeCleanup(onlyPaths: [directory.path])
        #expect(blocked.trashedCount == 0)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        // Empty selected execution must not be blocked by unrelated pending entries.
        #expect(state.executeCleanup(onlyPaths: []).failures.isEmpty)
        for _ in 0..<200 {
            if !state.cleanupIsMeasuring { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(state.cleanupItems.first?.sizeState == .measured)
        #expect(state.cleanupTotal == 123)
        #expect(state.cleanupItems.count == 1)
    }

    @Test @MainActor func removedMeasurementCannotPublishIntoRestagedItem() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 123).write(to: directory.appendingPathComponent("file"))
        let state = AppState()
        #expect(state.stage(source: "Old", path: directory.path))
        let oldID = state.cleanupItems.first?.id
        state.cleanupItems.removeAll()
        #expect(state.stage(source: "Replacement", path: directory.path, bytes: 999))
        let replacementID = state.cleanupItems.first?.id
        for _ in 0..<20 { await Task.yield() }
        #expect(replacementID != oldID)
        #expect(state.cleanupItems.first?.id == replacementID)
        #expect(state.cleanupItems.first?.bytes == 999)
        #expect(state.cleanupItems.first?.sizeState == .provided)
    }

    @Test @MainActor func singleFileStatRemainsSynchronous() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("file")
        try Data(repeating: 1, count: 41).write(to: file)
        let state = AppState()
        #expect(state.stage(source: "Test", path: file.path))
        #expect(state.cleanupItems.first?.bytes == 41)
        #expect(state.cleanupItems.first?.sizeState == .measured)
        #expect(!state.cleanupIsMeasuring)
    }

    @Test func exhaustedBudgetIsPartialNotAnExactEmptySize() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: directory.appendingPathComponent("file"))
        let result = AppState.measureStagedDirectory(at: directory.path, entryLimit: 0)
        #expect(!result.complete)
        #expect(result.bytes == 0)
        let unknown = CleanupItem(source: "Test", path: directory.path, bytes: 0, sizeState: .unknown)
        #expect(unknown.sizeLabel == "Size unknown")
        #expect(CleanupItem.sizeSummary([unknown]).contains("size unknown"))
    }

    @Test func knownTotalsSaturateAndIgnoreUnknownSizes() {
        let items = [
            CleanupItem(source: "Test", path: "/a", bytes: Int64.max),
            CleanupItem(source: "Test", path: "/b", bytes: 1),
            CleanupItem(source: "Test", path: "/c", bytes: Int64.max, sizeState: .unknown),
            CleanupItem(source: "Test", path: "/d", bytes: -1)
        ]
        #expect(CleanupItem.knownTotal(items) == Int64.max)
        #expect(CleanupItem.knownTotal(Array(items.suffix(2))) == 0)
    }

    @Test @MainActor func expansionPreservesSyntheticAndPartialFlags() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: directory.appendingPathComponent("file"))
        let collapsed = ScanNode(name: "Folder", path: directory.path, sizeBytes: 1,
                                 category: .other, fileCount: 1, isCollapsed: true, isPartial: true)
        let synthetic = ScanNode(name: "Other", path: "", sizeBytes: 1,
                                 category: .other, fileCount: 1, isSyntheticAggregate: true, isPartial: true)
        let state = AppState()
        state.scanRoot = ScanNode(name: "Root", path: "/", sizeBytes: 2,
                                  category: .other, fileCount: 2, children: [collapsed, synthetic], isPartial: true)
        state.expandNode(path: directory.path)
        for _ in 0..<200 {
            if state.scanRoot?.children.first?.isCollapsed == false { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(state.scanRoot?.children.first?.isCollapsed == false)
        #expect(state.scanRoot?.children.first?.isPartial == true)
        #expect(state.scanRoot?.children.last?.isSyntheticAggregate == true)
        #expect(state.scanRoot?.children.last?.isPartial == true)
        #expect(state.scanRoot?.children.last?.path == "")
        #expect(state.scanRoot?.isPartial == true)
    }
}
