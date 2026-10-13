import Foundation
import SQLite3
import Testing
@testable import DiskDoom

@Suite
struct CoreScanOptimizationTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskbuddy-core-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func breadthCapKeepsLargestAndAccountsForEveryFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for size in 1...120 {
            try Data(repeating: 0x61, count: size).write(to: root.appendingPathComponent("file-\(size)"))
        }
        var options = ScanOptions()
        options.maxChildrenPerDir = 7
        options.maxFiles = 20
        let result = await RealScanEngine().scan(root: root, label: "Wide", options: options)
        #expect(result.root.sizeBytes == 7_260)
        #expect(result.root.fileCount == 120)
        #expect(result.records.count == 20)
        #expect(result.root.children.filter { !$0.isSyntheticAggregate }.map(\.sizeBytes) == [120, 119, 118, 117, 116, 115, 114])
        let tail = try #require(result.root.children.last)
        #expect(tail.isSyntheticAggregate)
        #expect(!tail.isActionable)
        #expect(tail.path.isEmpty)
        #expect(tail.fileCount == 113)
        #expect(tail.sizeBytes == 6_441)
        #expect(!result.isPartial)
    }

    @Test func zeroBreadthCapProducesOnlySafeAggregate() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0, count: 17).write(to: root.appendingPathComponent("file"))
        var options = ScanOptions()
        options.maxChildrenPerDir = 0
        let result = await RealScanEngine().scan(root: root, label: "Zero", options: options)
        #expect(result.root.children.count == 1)
        #expect(result.root.children.first?.isSyntheticAggregate == true)
        #expect(result.root.children.first?.sizeBytes == 17)
    }

    @Test func streamedWalkPreservesHiddenExclusionAndNestedTotals() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested/inner", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 31).write(to: nested.appendingPathComponent("visible"))
        try Data(repeating: 0, count: 97).write(to: root.appendingPathComponent(".hidden"))
        try Data(repeating: 0, count: 101).write(to: root.appendingPathComponent("excluded"))
        var options = ScanOptions()
        options.includeHidden = false
        options.excludedPaths = [root.appendingPathComponent("excluded").path]
        let result = await RealScanEngine().scan(root: root, label: "Nested", options: options)
        #expect(result.root.sizeBytes == 31)
        #expect(result.root.fileCount == 1)
        #expect(result.records.count == 1)
    }

    @Test func streamedPackageMeasuresNestedBundlesAndSymlinksWithoutFollowing() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let nested = package.appendingPathComponent("Contents/Frameworks/Nested.framework", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 123).write(to: nested.appendingPathComponent("binary"))
        try Data(repeating: 0, count: 41).write(to: package.appendingPathComponent(".hidden"))
        try FileManager.default.createSymbolicLink(atPath: package.appendingPathComponent("loop").path, withDestinationPath: ".")
        let result = await RealScanEngine().scan(root: package, label: "Package", options: ScanOptions())
        #expect(result.root.isCollapsed)
        #expect(result.root.sizeBytes == 165) // 123 + 41 + one-byte symlink
        #expect(result.root.fileCount == 3)
        #expect(result.records.isEmpty)
        #expect(!result.isPartial)
    }

    @Test(arguments: [false, true])
    func directoryAliasExclusionsPreserveComponentBoundaries(denyViaAlias: Bool) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appendingPathComponent("real", isDirectory: true)
        let excluded = real.appendingPathComponent("excluded", isDirectory: true)
        let sibling = real.appendingPathComponent("excluded-keep", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 101).write(to: excluded.appendingPathComponent("omitted"))
        try Data(repeating: 0, count: 31).write(to: sibling.appendingPathComponent("included"))
        let alias = directory.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        let canonical = real.resolvingSymlinksInPath()
        var options = ScanOptions()
        options.followSymlinks = true
        options.excludedPaths = [(denyViaAlias ? alias : canonical).appendingPathComponent("excluded").path]
        let result = await RealScanEngine().scan(
            root: denyViaAlias ? canonical : alias, label: "Alias", options: options)
        #expect(result.root.sizeBytes == 31)
        #expect(result.root.fileCount == 1)
        #expect(result.records.count == 1)
        #expect(result.records.first?.path.hasSuffix("/excluded-keep/included") == true)
    }

    @Test func resolvingAcceptedEnumerationRootDoesNotFollowChildLinks() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("root", isDirectory: true)
        let outside = directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 31).write(to: root.appendingPathComponent("included"))
        try Data(repeating: 0, count: 101).write(to: outside.appendingPathComponent("not-followed"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("child-link"), withDestinationURL: outside)
        let result = await RealScanEngine().scan(root: root, label: "No child links", options: ScanOptions())
        #expect(result.root.sizeBytes == 31)
        #expect(result.root.fileCount == 1)
        #expect(result.records.count == 1)
    }

    @Test func cancelledScanIsPartial() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await RealScanEngine().scan(root: root, label: "Cancelled", options: ScanOptions())
        }
        let result = await task.value
        #expect(result.isPartial)
        #expect(result.records.isEmpty)
    }

    @Test func streamedSmartLeafIncludesNestedPackagesWithoutRecords() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("node_modules", isDirectory: true)
        let nested = store.appendingPathComponent("Dependency.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 67).write(to: nested.appendingPathComponent("binary"))
        try Data(repeating: 0, count: 23).write(to: store.appendingPathComponent(".hidden"))
        let result = await RealScanEngine().scan(root: root, label: "Smart leaf", options: ScanOptions())
        let leaf = try #require(result.root.children.first)
        #expect(leaf.isCollapsed)
        #expect(leaf.sizeBytes == 90)
        #expect(leaf.fileCount == 2)
        #expect(result.records.isEmpty)
    }

    @Test func databaseRoundTripsMoreThanFormerCommitChunk() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ScanDatabase(dbURL: directory.appendingPathComponent("Cache.sqlite"))
        let records = (0..<5_123).map { index in
            ScannedRecord(path: "/fixture/\(index)-é", bytes: Int64(index), physical: 512,
                          modified: Date(timeIntervalSince1970: 100), isDirectory: false, category: .other)
        }
        let root = ScanNode(name: "Fixture", path: "/fixture", sizeBytes: 42, category: .other, fileCount: records.count)
        try await database.saveScan(root: root, records: records, label: "Fixture", elapsed: 1)
        let cached = try #require(try await database.latestScan())
        #expect(try await database.fileCount(scanID: cached.id) == records.count)
        let tail = try await database.loadFiles(scanID: cached.id, limit: 200, offset: 5_000)
        #expect(tail.count == 123)
        #expect(tail.first?.path == records[5_000].path)
        #expect(tail.last?.bytes == 5_122)
        #expect(try await database.loadFiles(scanID: cached.id, limit: -1, offset: 0).isEmpty)
    }

    @Test func cancelledSaveDoesNotReplaceCompletedScan() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = ScanDatabase(dbURL: directory.appendingPathComponent("Cache.sqlite"))
        let root = ScanNode(name: "Fixture", path: "/fixture", sizeBytes: 42, category: .other, fileCount: 0)
        try await database.saveScan(root: root, records: [], label: "Completed", elapsed: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await database.saveScan(root: root, records: [], label: "Cancelled", elapsed: 1)
        }
        do {
            try await task.value
            Issue.record("A cancelled save must throw")
        } catch is CancellationError {
            // Expected: completed cache survives, no cancelled row inserted.
        }
        #expect(try await database.latestScan()?.label == "Completed")
    }

    @Test func lateInsertFailureRollsBackBeyondFormerCommitBoundary() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dbURL = directory.appendingPathComponent("Cache.sqlite")
        let database = ScanDatabase(dbURL: dbURL)
        let root = ScanNode(name: "Fixture", path: "/fixture", sizeBytes: 42, category: .other, fileCount: 0)
        try await database.saveScan(root: root, records: [], label: "Completed", elapsed: 1)

        var handle: OpaquePointer?
        #expect(sqlite3_open(dbURL.path, &handle) == SQLITE_OK)
        let connection = try #require(handle)
        defer { sqlite3_close(connection) }
        // Fail after the old 5,000-row COMMIT point, deterministically.
        #expect(sqlite3_exec(connection, """
            CREATE TRIGGER reject_late_record BEFORE INSERT ON scan_files
            WHEN NEW.path = '/fixture/5001'
            BEGIN SELECT RAISE(ABORT, 'test insertion failure'); END;
            """, nil, nil, nil) == SQLITE_OK)
        let records = (0..<5_123).map { index in
            ScannedRecord(path: "/fixture/\(index)", bytes: 1, physical: 512,
                          modified: Date(timeIntervalSince1970: 100), isDirectory: false, category: .other)
        }
        do {
            try await database.saveScan(root: root, records: records, label: "Failed", elapsed: 1)
            Issue.record("The injected insertion failure must throw")
        } catch is ScanDatabaseError {
            // Expected: neither scan metadata nor committed early rows survive.
        }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(connection, "SELECT (SELECT COUNT(*) FROM scans), (SELECT COUNT(*) FROM scan_files)", -1, &statement, nil) == SQLITE_OK)
        let counts = try #require(statement)
        defer { sqlite3_finalize(counts) }
        #expect(sqlite3_step(counts) == SQLITE_ROW)
        #expect(sqlite3_column_int64(counts, 0) == 1)
        #expect(sqlite3_column_int64(counts, 1) == 0)
    }
}
