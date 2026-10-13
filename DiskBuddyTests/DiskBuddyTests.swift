//
//  DiskBuddyTests.swift
//  DiskBuddyTests
//
//  Created by surjeet on 07/09/26.
//

import Testing
import Foundation
@testable import DiskDoom

// MARK: - Snapshot persistence + cleanup queue (single serialized suite:
// these tests share the ScanStore.directoryOverride static, so they must
// never interleave with each other or the real home directory leaks in).

@Suite(.serialized)
struct PersistenceTests {
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskbuddy-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func saveAndLoadRoundTrip() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        ScanStore.directoryOverride = dir
        defer { ScanStore.directoryOverride = nil }

        let date = Date()
        ScanStore.saveSnapshot(
            date: date, label: "Manual", target: "Full Mac",
            totalBytes: 123_456, files: 42, topDirs: ["Users": 100_000, "System": 23_456])

        let loaded = ScanStore.loadSnapshots(retention: 30)
        #expect(loaded.count == 1)
        #expect(loaded[0].label == "Manual")
        #expect(loaded[0].target == "Full Mac")
        #expect(loaded[0].totalBytes == 123_456)
        #expect(loaded[0].files == 42)

        let topDirs = ScanStore.topDirs(for: loaded[0])
        #expect(topDirs?["Users"] == 100_000)
        #expect(topDirs?["System"] == 23_456)
    }

    @Test func uniqueNamesForSameSecondSaves() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        ScanStore.directoryOverride = dir
        defer { ScanStore.directoryOverride = nil }

        let now = Date()
        ScanStore.saveSnapshot(date: now, label: "A", target: "Full Mac", totalBytes: 1, files: 1, topDirs: [:])
        ScanStore.saveSnapshot(date: now, label: "B", target: "Full Mac", totalBytes: 2, files: 2, topDirs: [:])

        let loaded = ScanStore.loadSnapshots(retention: 30)
        #expect(loaded.count == 2, "two snapshots saved within the same second must not overwrite each other")
    }

    @Test func deleteSnapshotRemovesPersistedFile() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        ScanStore.directoryOverride = dir
        defer { ScanStore.directoryOverride = nil }

        let date = Date()
        ScanStore.saveSnapshot(date: date, label: "Scan", target: "Full Mac", totalBytes: 9, files: 9, topDirs: [:])
        #expect(ScanStore.loadSnapshots(retention: 30).count == 1)

        ScanStore.removeSnapshot(date: date)
        #expect(ScanStore.loadSnapshots(retention: 30).isEmpty, "deleted snapshot must not reappear on next load")
    }

    @Test func retentionPrunesOldestBeyondLimit() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        ScanStore.directoryOverride = dir
        defer { ScanStore.directoryOverride = nil }

        let base = Date()
        for i in 0..<5 {
            ScanStore.saveSnapshot(
                date: base.addingTimeInterval(Double(-i)), label: "S\(i)",
                target: "Full Mac", totalBytes: Int64(i), files: i, topDirs: [:])
        }
        let loaded = ScanStore.loadSnapshots(retention: 3)
        #expect(loaded.count == 3, "retention must prune snapshots beyond the limit")
        // Newest survive.
        #expect(loaded.allSatisfy { $0.totalBytes <= 2 })
    }

    // MARK: AppState cleanup queue + snapshot deletion (MainActor)

    @MainActor
    private func makeTempFile(_ name: String = "stage-me.txt", bytes: Int = 128) throws -> URL {
        // Destructive-operation fixtures must not live under the protected
        // system temporary tree (/private/var/folders).
        let directory = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let url = directory
            .appendingPathComponent("diskbuddy-stage-\(UUID().uuidString)-\(name)")
        try Data(repeating: 0x61, count: bytes).write(to: url)
        return url
    }

    @MainActor
    @Test func stageRejectsNonFilesystemPaths() throws {
        let state = AppState()
        state.stage(source: "Photos", path: "Photo duplicates (36 sets)", bytes: 1_000)
        state.stage(source: "AgeMap", path: "Files older than 2+ years", bytes: 1_000)
        state.stage(source: "Fake", path: "relative/path.txt", bytes: 1_000)
        state.stage(source: "Missing", path: "/nonexistent/diskbuddy/missing.txt", bytes: 1_000)
        #expect(state.cleanupItems.isEmpty, "synthetic labels, relative paths, and missing files must never enter the cleanup queue")
    }

    @MainActor
    @Test func stageAcceptsRealFileAndMeasuresSize() throws {
        let file = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let state = AppState()
        state.stage(source: "Test", path: file.path)
        #expect(state.cleanupItems.count == 1)
        #expect(state.cleanupItems[0].bytes == 128, "staging without explicit bytes must measure the file on disk")

        // Duplicate path is ignored.
        state.stage(source: "Test", path: file.path, bytes: 999)
        #expect(state.cleanupItems.count == 1)
        #expect(state.cleanupItems[0].bytes == 128)
    }

    @MainActor
    @Test func deleteSnapshotViaAppStateDeletesPersistedFile() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        ScanStore.directoryOverride = dir
        defer { ScanStore.directoryOverride = nil }

        let state = AppState()
        state.saveSnapshotFromCurrentScan(label: "Manual") // no scanRoot → no-op, safe
        #expect(state.snapshots.isEmpty)

        // Seed a snapshot directly, then delete through AppState.
        ScanStore.saveSnapshot(date: Date(), label: "Scan", target: "Full Mac", totalBytes: 5, files: 5, topDirs: [:])
        state.snapshots = ScanStore.loadSnapshots(retention: 30)
        #expect(state.snapshots.count == 1)

        state.deleteSnapshot(state.snapshots[0])
        #expect(state.snapshots.isEmpty)
        #expect(ScanStore.loadSnapshots(retention: 30).isEmpty, "AppState delete must remove the JSON file, not just the in-memory row")
    }

    @MainActor
    @Test func trashRejectsMissingAndSyntheticPaths() {
        let result = TrashService.trash(paths: [
            ("/definitely/not/here.txt", 10),
            ("Photo duplicates (36 sets)", 10),
        ])
        #expect(result.trashedCount == 0)
        #expect(result.failures.count == 2)
        #expect(result.failures.allSatisfy { $0.reason == "File no longer exists" })
    }

    @MainActor
    @Test func trashMovesRealFileToTrash() throws {
        let file = try makeTempFile("trash-me.txt")
        let result = TrashService.trash(paths: [(file.path, 128)])
        #expect(result.trashedCount == 1)
        #expect(result.trashedBytes == 128)
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path), "source file must be gone after trashing")
    }
}

// MARK: - Scan engine: exclusion boundary + basic walk

@Suite
struct RealScanEngineTests {
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskbuddy-scan-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        for dir in ["Cache", "CacheBackup", "Docs"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir, isDirectory: true), withIntermediateDirectories: true)
        }
        try Data("cache data".utf8).write(to: root.appendingPathComponent("Cache/blob.bin"))
        try Data("cache backup data".utf8).write(to: root.appendingPathComponent("CacheBackup/blob.bin"))
        try Data("doc".utf8).write(to: root.appendingPathComponent("Docs/readme.txt"))
        return root
    }

    @Test func excludedPathMatchesOnComponentBoundary() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = RealScanEngine()
        let options = ScanOptions(
            excludedPaths: [root.appendingPathComponent("Cache").path])
        let result = await engine.scan(root: root, label: "Test", options: options)

        let paths = Set(result.records.map(\.path))
        #expect(!paths.contains(where: { $0.contains("/Cache/") }), "excluded dir must be skipped")
        #expect(paths.contains(where: { $0.contains("CacheBackup") }),
                "a sibling whose name merely shares a prefix must NOT be excluded")
        #expect(paths.contains(where: { $0.contains("Docs") }))
    }

    @Test func scanProducesSizedTreeAndRecords() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = RealScanEngine()
        let result = await engine.scan(root: root, label: "Test", options: ScanOptions())
        #expect(result.root.children.count == 3)
        #expect(result.root.sizeBytes > 0)
        #expect(!result.records.isEmpty)
        #expect(!result.isPartial)
    }
}

// MARK: - Squarified treemap layout

@Suite
struct TreemapLayoutTests {
    private func makeNodes(_ sizes: [Int64]) -> [ScanNode] {
        sizes.enumerated().map { i, size in
            ScanNode(name: "n\(i)", path: "/n\(i)", sizeBytes: size, category: .other, fileCount: 1)
        }
    }

    @Test func layoutCoversWholeRectExactly() {
        let nodes = makeNodes([500, 250, 125, 60, 30, 20, 10, 5])
        let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let cells = TreemapLayout.layout(nodes: nodes, in: rect)
        #expect(cells.count == nodes.count)
        let totalArea = cells.reduce(CGFloat(0)) { $0 + $1.rect.width * $1.rect.height }
        #expect(abs(totalArea - rect.width * rect.height) < 1.0, "cells must tile the rect without gaps")
        for cell in cells {
            #expect(cell.rect.width > 0 && cell.rect.height > 0)
            #expect(rect.contains(cell.rect), "cells must stay inside bounds")
        }
    }

    @Test func squarifiedBeatsSliceAndDiceOnAspectRatios() {
        // Highly skewed input is the worst case for slice-and-dice.
        var sizes: [Int64] = []
        for i in 0..<40 { sizes.append(Int64(1_000_000 >> min(i, 19))) }
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cells = TreemapLayout.layout(nodes: makeNodes(sizes), in: rect)
        // Every cell reasonably square-ish: aspect ratio ≤ ~8 for all but
        // the tiniest slivers of area (last 10% by area may be thinner).
        let ranked = cells.sorted { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }
        let bigCells = ranked.prefix(max(1, ranked.count * 9 / 10))
        for cell in bigCells {
            let ratio = max(cell.rect.width / cell.rect.height, cell.rect.height / cell.rect.width)
            #expect(ratio < 8.0, "squarified cells should stay near-square, got ratio \(ratio) for \(cell.node.name)")
        }
    }

    @Test func emptyInputProducesNoCells() {
        #expect(TreemapLayout.layout(nodes: [], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        #expect(TreemapLayout.layout(nodes: makeNodes([0, 0]), in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    }
}

// MARK: - Dev cache catalogue (real paths only)

@Suite
struct DevCacheEngineTests {
    @Test func scanFindsOnlyExistingPaths() {
        // The engine must only report what actually exists on this machine
        // (a typical dev Mac has Homebrew + Xcode caches; CI might not —
        // so assert the invariant, not specific tools).
        let engine = DevCacheEngine()
        engine.scan()
        let items = engine.items
        for item in items {
            #expect(FileManager.default.fileExists(atPath: item.path),
                    "reported path must exist: \(item.path)")
            #expect(item.bytes > 0, "reported size must be measured: \(item.path)")
        }
        // Total must equal the sum of parts (no fabricated totals).
        #expect(engine.totalBytes == items.reduce(0) { $0 + $1.bytes })
    }
}

// MARK: - App inventory cache round-trip (Codable)

@Suite
struct AppEntryCodableTests {
    @Test func encodeDecodeRoundTripPreservesFields() throws {
        let entry = AppEntry(
            name: "TestApp", bundleID: "com.test.app", bundlePath: "/Applications/TestApp.app",
            version: "1.0", bundleBytes: 1_000,
            artifacts: [AppArtifactInfo(path: "/Users/x/Library/Caches/com.test.app", bytes: 500, kind: "Caches")],
            installDate: Date(timeIntervalSince1970: 1_700_000_000), isStale: false)
        let data = try JSONEncoder().encode([entry])
        let decoded = try JSONDecoder().decode([AppEntry].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded[0].bundleID == "com.test.app")
        #expect(decoded[0].bundleBytes == 1_000)
        #expect(decoded[0].artifacts.count == 1)
        #expect(decoded[0].artifacts[0].bytes == 500)
        #expect(decoded[0].totalBytes == 1_500)
    }
}

// MARK: - Menu bar monitor (formatting + space hogs from real data)

@Suite
@MainActor
struct MenuBarMonitorTests {
    @Test func menuBarTitleFormatting() {
        #expect(MenuBarMonitor.formatMenuBarTitle(free: 45 * 1_073_741_824) == "45G")
        #expect(MenuBarMonitor.formatMenuBarTitle(free: 1_099_511_627_776) == "1.0T")
        #expect(MenuBarMonitor.formatMenuBarTitle(free: 890 * 1_048_576) == "890M")
        #expect(MenuBarMonitor.formatMenuBarTitle(free: 0) == "0M")
    }

    @Test func pollReadsRealDiskSpace() throws {
        let monitor = MenuBarMonitor()
        monitor.pollDiskSpace()
        let capacity = try #require(monitor.currentCapacity.availableValue, "root volume capacity must be readable")
        #expect(capacity.totalBytes > 0)
        #expect(capacity.freeBytes >= 0)
        #expect(capacity.usedPercent >= 0 && capacity.usedPercent <= 100)
        #expect(monitor.spaceState != .unknown)
        #expect(!monitor.menuBarTitle.isEmpty && monitor.menuBarTitle != "—")
        #expect(monitor.lastUpdated != nil)
    }

    @Test func spaceHogsFromScanPrefersLargestAndSkipsSmallFiles() {
        let monitor = MenuBarMonitor()
        let dayAgo = Date().addingTimeInterval(-86_400)
        let records = [
            ScannedRecord(path: "/Users/x/big-movie.mov", bytes: 3_000_000_000, physical: 3_000_000_000, modified: dayAgo, isDirectory: false, category: .other),
            ScannedRecord(path: "/Users/x/medium.bin", bytes: 500_000_000, physical: 500_000_000, modified: dayAgo, isDirectory: false, category: .other),
            ScannedRecord(path: "/Users/x/tiny.txt", bytes: 1_000, physical: 1_000, modified: dayAgo, isDirectory: false, category: .other), // below 100MB cutoff
            ScannedRecord(path: "/Users/x/BigFolder", bytes: 9_000_000_000, physical: 9_000_000_000, modified: dayAgo, isDirectory: true, category: .other), // directory, skipped
        ]
        let apps = [
            AppEntry(name: "HugeApp", bundleID: "com.huge", bundlePath: "/Applications/HugeApp.app",
                     version: "1", bundleBytes: 2_000_000_000, artifacts: [], installDate: nil, isStale: false),
            AppEntry(name: "StaleApp", bundleID: "com.stale", bundlePath: "",
                     version: "1", bundleBytes: 8_000_000_000, artifacts: [], installDate: nil, isStale: true), // stale, skipped
        ]
        monitor.updateFromScan(records: records, apps: apps, litterScore: 42, healthGrade: "B", scanDate: Date())

        #expect(monitor.topSpaceHogs.count == 3, "two files above the 100MB cutoff + one app")
        #expect(monitor.topSpaceHogs[0].size == 3_000_000_000, "sorted by size descending (3GB > 2GB > 500MB)")
        #expect(monitor.topSpaceHogs[1].name == "HugeApp")
        #expect(monitor.topSpaceHogs[2].name == "medium.bin")
        #expect(!monitor.topSpaceHogs.contains { $0.name == "tiny.txt" })
        #expect(!monitor.topSpaceHogs.contains { $0.name == "StaleApp" })
        #expect(monitor.litterScore == 42)
        #expect(monitor.healthGrade == "B")
        #expect(monitor.lastScanDate != nil)
    }
}

// MARK: - Developer workspace tools (markers, classification, glob, measure)

@Suite
struct DeveloperWorkspaceTests {
    @Test func markerDetection() {
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "App.xcodeproj", parentPath: "/Users/x/Projects/App") == .xcode)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "App.xcworkspace", parentPath: "/Users/x/App") == .xcodeWorkspace)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "package.json", parentPath: "/Users/x/webapp") == .nodeProject)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "package.json", parentPath: "/x/node_modules/react") == nil,
                "markers inside node_modules are not project roots")
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "Cargo.toml", parentPath: "/Users/x/backend") == .rust)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "go.mod", parentPath: "/Users/x/svc") == .go)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "pyproject.toml", parentPath: "/Users/x/ml") == .python)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "Package.swift", parentPath: "/Users/x/lib") == .swiftPackage)
        #expect(DeveloperWorkspaceScanner.detectMarker(childName: "index.js", parentPath: "/Users/x") == nil)
    }

    @Test func componentClassification() {
        func classify(_ name: String) -> ProjectComponent {
            DeveloperWorkspaceScanner.classifyProjectComponent(name: name, path: "/p/\(name)", size: 1, projectType: .nodeProject)
        }
        let nodeModules = classify("node_modules")
        #expect(nodeModules.category == .dependencies)
        #expect(nodeModules.canClean)
        #expect(nodeModules.cleanRisk == .safeSlow)

        let git = classify(".git")
        #expect(!git.canClean, ".git must never be cleanable")
        #expect(git.cleanRisk == .dangerous)

        let env = classify(".env")
        #expect(!env.canClean, ".env holds secrets — never cleanable")
        #expect(env.cleanRisk == .dangerous)

        #expect(classify("DerivedData").category == .build)
        #expect(classify("__pycache__").category == .build)
        #expect(classify(".next").category == .build)
        #expect(classify("target").cleanRisk == .safeSlow)
        #expect(classify(".venv").category == .environment)
        #expect(classify("Sources").canClean == false)
        #expect(classify("README.md").category == .config)
    }

    @Test func scanSyncFindsProjectsInFixtureTree() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("devws-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        // Project A: Xcode.
        try fm.createDirectory(at: root.appendingPathComponent("ios-app/App.xcodeproj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("ios-app/Sources"), withIntermediateDirectories: true)
        try Data("swift code".utf8).write(to: root.appendingPathComponent("ios-app/Sources/Main.swift"))
        try fm.createDirectory(at: root.appendingPathComponent("ios-app/DerivedData/build"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2048).write(to: root.appendingPathComponent("ios-app/DerivedData/build/blob"))
        // Project B: node (nested one level deeper).
        try fm.createDirectory(at: root.appendingPathComponent("web/nested-site"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("web/nested-site/package.json"))
        try fm.createDirectory(at: root.appendingPathComponent("web/nested-site/node_modules/react"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: root.appendingPathComponent("web/nested-site/node_modules/react/index.js"))
        // Decoy: a plain folder with no markers (search must not report it).
        try fm.createDirectory(at: root.appendingPathComponent("just-files"), withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: root.appendingPathComponent("just-files/readme.txt"))
        defer { try? fm.removeItem(at: root) }

        let projects = await Task.detached {
            DeveloperWorkspaceScanner.scanSync(searchPaths: [root.path])
        }.value
        #expect(projects.count == 2, "Xcode project + node project, decoy excluded")
        let xcode = projects.first { $0.type == .xcode }
        #expect(xcode != nil, "App.xcodeproj (suffix marker) must detect an Xcode project")
        #expect(xcode?.components.contains { $0.name == "DerivedData" && $0.size == 2048 } == true)
        let node = projects.first { $0.type == .nodeProject }
        #expect(node != nil, "package.json must detect a Node project")
        #expect(node?.components.contains { $0.name == "node_modules" && $0.size == 4096 } == true)
        #expect(node?.cleanableSize == 4096, "package.json itself isn't cleanable, node_modules is")
    }
}

// MARK: - Pro cache glob + measure

@Suite
struct ProCacheScannerTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("procache-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("houdini_temp/sim"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("houdini_cache"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("unrelated"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("My Project.fcpbundle/Render Files"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("houdini_temp/sim/a.vdb"))
        try Data(repeating: 0, count: 50).write(to: root.appendingPathComponent("houdini_cache/b.vdb"))
        try Data(repeating: 0, count: 25).write(to: root.appendingPathComponent("My Project.fcpbundle/Render Files/frame.mov"))
        return root
    }

    @Test func prefixGlobMatchesOnlyMatchingDirs() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let matches = ProCacheScanner.expandGlob("\(root.path)/houdini*")
        #expect(Set(matches.map { ($0 as NSString).lastPathComponent }) == ["houdini_temp", "houdini_cache"])
    }

    @Test func suffixGlobWithSubpathResolvesFCPRenderFiles() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let matches = ProCacheScanner.expandGlob("\(root.path)/*.fcpbundle/Render Files")
        #expect(matches.count == 1)
        #expect(matches[0].hasSuffix("Render Files"))
        #expect((matches[0] as NSString).lastPathComponent == "Render Files")
    }

    @Test func globWithNoMatchesReturnsEmpty() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ProCacheScanner.expandGlob("\(root.path)/blender*").isEmpty)
        #expect(ProCacheScanner.expandGlob("\(root.path)/nope/deeper").isEmpty)
    }

    @Test func measureCountsBytesAndFiles() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let m = ProCacheScanner.measure(path: root.appendingPathComponent("houdini_temp").path)
        #expect(m.bytes == 100)
        #expect(m.files == 1)
    }
}

// MARK: - Disk Forecast engine (usage history, regression, no fabrication)

@Suite(.serialized)
@MainActor
struct ForecastEngineTests {
    private func makeEngine(dir: inout URL?) -> DiskForecastEngine {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("forecast-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        DiskForecastEngine.directoryOverride = url
        dir = url
        return DiskForecastEngine()
    }

    private let GB: Int64 = 1_000_000_000

    @Test func needsTwoSnapshots() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        await engine.compute()
        #expect(engine.forecast == nil)
        #expect(engine.alerts.contains { $0.severity == .info || !$0.title.isEmpty })

        engine.recordSnapshot(totalCapacity: 500 * GB, usedSize: 100 * GB, freeSize: 400 * GB, source: .launch)
        await engine.compute()
        #expect(engine.forecast == nil, "a single snapshot can't define a trend")
    }

    @Test func decliningTrendReportsNoFillDate() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        // Used fell 300 → 200 GB over 10 days.
        engine.seedHistory([
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-10 * 86_400),
                          totalCapacity: 500 * GB, usedSize: 300 * GB, freeSize: 200 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date(),
                          totalCapacity: 500 * GB, usedSize: 200 * GB, freeSize: 300 * GB,
                          categoryBreakdown: [:], source: .scan),
        ])
        await engine.compute()

        #expect(engine.forecast != nil)
        #expect(engine.forecast?.daysUntilFull == nil, "shrinking usage must not predict a full-disk date")
        #expect(engine.forecast?.trendDirection == .shrinking)
        #expect((engine.forecast?.dailyChangeBytes ?? 1) < 0)
    }

    @Test func growingTrendComputesDaysUntilFull() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        // +10 GB/day sustained over 8 days, 50 GB free at latest → ~5 days to full.
        // Needs >= 3 points spanning >= 7 days: extrapolating a fill date from
        // two measurements of the same afternoon produced "0 days until full".
        engine.seedHistory([
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-8 * 86_400),
                          totalCapacity: 500 * GB, usedSize: 350 * GB, freeSize: 150 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-4 * 86_400),
                          totalCapacity: 500 * GB, usedSize: 400 * GB, freeSize: 100 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date(),
                          totalCapacity: 500 * GB, usedSize: 450 * GB, freeSize: 50 * GB,
                          categoryBreakdown: [:], source: .scan),
        ])
        await engine.compute()

        #expect(engine.forecast != nil)
        #expect(engine.forecast?.trendDirection == .growing)
        let days = engine.forecast?.daysUntilFull
        #expect(days != nil && days! > 0 && days! < 3_650, "growing usage with 50 GB free must predict a positive fill date")
    }

    @Test func insufficientHistoryDoesNotPredictAFillDate() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        // Regression test: two snapshots 4 minutes apart (exactly what a single
        // launch produces — cached-scan hydration, then the launch job) used
        // to yield ~288 GB/day and a confident "Disk full in 0 days".
        let now = Date()
        engine.seedHistory([
            UsageSnapshot(id: UUID(), timestamp: now.addingTimeInterval(-240),
                          totalCapacity: 500 * GB, usedSize: 400 * GB, freeSize: 100 * GB,
                          categoryBreakdown: [:], source: .scan),
            UsageSnapshot(id: UUID(), timestamp: now,
                          totalCapacity: 500 * GB, usedSize: 401 * GB, freeSize: 99 * GB,
                          categoryBreakdown: [:], source: .launch),
        ])
        await engine.compute()

        #expect(engine.forecast?.daysUntilFull == nil,
                "must not publish a fill date from 4 minutes of history")
        #expect(engine.forecast?.hasReliableProjection == false)
        #expect(engine.forecast?.projectedUsage30Days == engine.forecast?.currentUsed,
                "projections must fall back to current usage, not extrapolate")
        #expect(!engine.alerts.contains { $0.title.contains("Disk full in") },
                "no 'Disk full in 0 days' alert from a same-afternoon pair")
    }

    @Test func subDayFillEstimateIsNotRoundedToZero() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        // Grows fast enough that the naive fill estimate is under a day.
        // Rounding produced the alarming "Disk full in 0 days".
        let now = Date()
        engine.seedHistory([
            UsageSnapshot(id: UUID(), timestamp: now.addingTimeInterval(-9 * 86_400),
                          totalCapacity: 2_000 * GB, usedSize: 1_000 * GB, freeSize: 1_000 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: now.addingTimeInterval(-8 * 86_400),
                          totalCapacity: 2_000 * GB, usedSize: 1_400 * GB, freeSize: 600 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: now,
                          totalCapacity: 2_000 * GB, usedSize: 1_800 * GB, freeSize: 200 * GB,
                          categoryBreakdown: [:], source: .scan),
        ])
        await engine.compute()

        if let days = engine.forecast?.daysUntilFull {
            #expect(days >= 1, "a fill estimate must never be presented as 0 days")
        }
    }

    @Test func recordsWithinHourAreDeduplicated() throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        engine.recordSnapshot(totalCapacity: 500 * GB, usedSize: 100 * GB, freeSize: 400 * GB, source: .launch)
        engine.recordSnapshot(totalCapacity: 500 * GB, usedSize: 120 * GB, freeSize: 380 * GB, source: .scan)
        #expect(engine.history.count == 1, "launch + scan within the same hour collapse into one entry")
        #expect(engine.history[0].usedSize == 120 * GB, "the later entry (scan) wins")
    }

    @Test func categoryGrowthFromBreakdowns() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        engine.recordSnapshot(
            totalCapacity: 500 * GB, usedSize: 100 * GB, freeSize: 400 * GB,
            categoryBreakdown: ["caches": 10 * GB, "logs": 2 * GB], source: .launch)
        // Force distinct timestamps: mutate the last entry via a new record
        // after moving the first one back in time is not public API — instead
        // record with an hour gap by manipulating engine history is not
        // available; verify via two-day simulation using direct history seeds:
        engine.seedHistory([
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-8 * 86_400),
                          totalCapacity: 500 * GB, usedSize: 100 * GB, freeSize: 400 * GB,
                          categoryBreakdown: ["caches": 10 * GB, "logs": 2 * GB], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-4 * 86_400),
                          totalCapacity: 500 * GB, usedSize: 114 * GB, freeSize: 386 * GB,
                          categoryBreakdown: ["caches": 14 * GB, "logs": 2 * GB], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date(),
                          totalCapacity: 500 * GB, usedSize: 128 * GB, freeSize: 372 * GB,
                          categoryBreakdown: ["caches": 18 * GB, "logs": 2 * GB], source: .scan),
        ])
        await engine.compute()

        let caches = engine.forecast?.categoryGrowth.first { $0.category == "caches" }
        #expect(caches?.changeBytes == 8 * GB, "caches grew by 8 GB over 8 days")
        #expect(abs((caches?.dailyRateBytes ?? 0) - 1 * GB) < 10, "8 GB over 8 days = 1 GB/day (± rounding)")
    }

    @Test func growingTrendDaysUntilFullMath() async throws {
        var dir: URL?
        let engine = makeEngine(dir: &dir)
        defer { try? FileManager.default.removeItem(at: dir!); DiskForecastEngine.directoryOverride = nil }

        // 100 GB total, used 40→50 GB over 8 days = +1.25 GB/day, 50 GB free → 40 days.
        // Three points over 8 days: the engine now requires >= 3 snapshots and
        // >= 7 days of span before publishing a fill date.
        engine.seedHistory([
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-8 * 86_400),
                          totalCapacity: 100 * GB, usedSize: 40 * GB, freeSize: 60 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date().addingTimeInterval(-4 * 86_400),
                          totalCapacity: 100 * GB, usedSize: 45 * GB, freeSize: 55 * GB,
                          categoryBreakdown: [:], source: .launch),
            UsageSnapshot(id: UUID(), timestamp: Date(),
                          totalCapacity: 100 * GB, usedSize: 50 * GB, freeSize: 50 * GB,
                          categoryBreakdown: [:], source: .scan),
        ])
        await engine.compute()
        #expect(engine.forecast?.daysUntilFull == 40, "50 GB free at +1.25 GB/day = 40 days")
        #expect(abs((engine.forecast?.dailyChangeBytes ?? 0) - Int64(1.25 * Double(GB))) < 1_000_000,
                "+1.25 GB/day (± rounding)")
        #expect(engine.forecast?.hasReliableProjection == true)
        // 50 GB + 30 days * 1.25 GB/day = 87.5 GB, under the 100 GB cap.
        #expect(abs((engine.forecast?.projectedUsage30Days ?? 0) - Int64(87.5 * Double(GB))) < 1_000_000,
                "30-day projection = 87.5 GB")
    }
}
