import Foundation
import Testing
import CoreGraphics
@testable import DiskDoom

// MARK: - Feature parity: ignore rules, priorities, removal methods, hashing

private func makeDefaults() -> (UserDefaults, String) {
    let name = "diskbuddy.parity.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        fatalError("Could not create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: name)
    for key in ["ignorePaths", "ignoreExtensions", "priorityFolders", "priorityFileExtensions"] {
        defaults.removeObject(forKey: key)
    }
    return (defaults, name)
}

private func tempDirectory() throws -> URL {
    // The system temp directory lives under /private/var/folders, which the
    // deletion backstop intentionally treats as protected. Use a user cache
    // folder so removal tests exercise real, removable files.
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches", isDirectory: true)
    let url = base.appendingPathComponent("diskbuddy-parity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite(.serialized)
struct IgnoreRulesTests {
    @MainActor
    @Test func pathsAndExtensionsFilterEverything() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let rules = IgnoreRules(defaults: defaults)

        #expect(rules.addPath("/Users/example/Secret"))
        #expect(rules.addPath("/Users/example/Secret") == false)
        #expect(!rules.addPath("relative/path"))
        #expect(rules.addExtension(".DMG"))
        #expect(rules.addExtension("dmg") == false)
        #expect(rules.ignoredExtensions == ["dmg"])

        #expect(rules.isPathIgnored("/Users/example/Secret/file.txt"))
        #expect(rules.isPathIgnored("/Users/example/Secretive/file.txt") == false)
        #expect(rules.isExtensionIgnored("/Users/example/installer.DMG"))
        #expect(rules.shouldIgnore(path: "/Volumes/Disk/thing.dmg"))

        let records = [
            ScannedRecord(path: "/Users/example/Secret/a.txt", bytes: 1, physical: 1,
                          modified: .distantPast, isDirectory: false, category: .other),
            ScannedRecord(path: "/Users/example/Public/b.txt", bytes: 1, physical: 1,
                          modified: .distantPast, isDirectory: false, category: .other),
            ScannedRecord(path: "/Users/example/Public/c.dmg", bytes: 1, physical: 1,
                          modified: .distantPast, isDirectory: false, category: .other),
        ]
        let filtered = rules.filter(records)
        #expect(filtered.map(\.path) == ["/Users/example/Public/b.txt"])
    }

    @MainActor
    @Test func rulesPersistAcrossInstances() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = IgnoreRules(defaults: defaults)
        first.addPath("/tmp/ignored")
        first.addExtension("zip")

        let second = IgnoreRules(defaults: defaults)
        #expect(second.ignoredPaths == ["/tmp/ignored"])
        #expect(second.ignoredExtensions == ["zip"])
    }
}

@Suite(.serialized)
struct ScanPriorityTests {
    @MainActor
    @Test func folderPriorityWinsAndFallsBackToTypePriority() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ScanPriorityStore(defaults: defaults)

        store.addFolder("/Users/example/Keep")
        store.addExtension("heic")

        let files = [
            DuplicateFile(path: "/Users/example/Other/photo.jpg", bytes: 100),
            DuplicateFile(path: "/Users/example/Keep/photo.jpg", bytes: 100),
        ]
        #expect(store.preferredKeep(in: files)?.path == "/Users/example/Keep/photo.jpg")

        let typeOnly = [
            DuplicateFile(path: "/Users/example/Other/photo.jpg", bytes: 100),
            DuplicateFile(path: "/Users/example/Other/photo.heic", bytes: 100),
        ]
        #expect(store.preferredKeep(in: typeOnly)?.path == "/Users/example/Other/photo.heic")
    }

    @MainActor
    @Test func reorderingChangesPriority() throws {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ScanPriorityStore(defaults: defaults)
        store.addFolder("/A")
        store.addFolder("/B")
        #expect(store.folderRank(forPath: "/A/file") < store.folderRank(forPath: "/B/file"))
        store.moveFolder(from: 1, to: 0)
        #expect(store.folderRank(forPath: "/B/file") < store.folderRank(forPath: "/A/file"))
    }
}

@Suite(.serialized)
struct RemovalServiceTests {
    @Test func moveToDestinationKeepsFileAndAvoidsOverwrite() throws {
        let root = try tempDirectory()
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: first.appendingPathComponent("file.txt"))
        try Data("two".utf8).write(to: second.appendingPathComponent("file.txt"))

        let resultA = RemovalService.remove(
            items: [(first.appendingPathComponent("file.txt").path, 3)],
            method: .move, destination: destination.path, overwrite: false)
        #expect(resultA.removedCount == 1)
        #expect(resultA.failures.isEmpty)

        let resultB = RemovalService.remove(
            items: [(second.appendingPathComponent("file.txt").path, 3)],
            method: .move, destination: destination.path, overwrite: false)
        #expect(resultB.removedCount == 1)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("file.txt").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("file (2).txt").path))
    }

    @Test func permanentDeleteRemovesFileButRefusesSystemPath() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("trash-me.txt")
        try Data("x".utf8).write(to: file)

        let removed = RemovalService.remove(items: [(file.path, 1)], method: .permanent)
        #expect(removed.removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        let refused = RemovalService.remove(items: [("/System", 0)], method: .permanent)
        #expect(refused.removedCount == 0)
        #expect(refused.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: "/System"))
    }

    @Test func moveRefusesDestinationInsideSource() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("inside.txt")
        try Data("x".utf8).write(to: file)

        let result = RemovalService.remove(
            items: [(folder.path, 1)], method: .move,
            destination: folder.appendingPathComponent("nested").path, overwrite: false)
        #expect(result.removedCount == 0)
        #expect(result.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }
}

@Suite(.serialized)
struct SimilarPhotoHashTests {
    private func image(inverted: Bool) throws -> CGImage {
        let width = 9, height = 8
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue))
        for x in 0..<width {
            let step = 28 * x
            let value = inverted ? 255 - step : step
            context.setFillColor(gray: CGFloat(value) / 255, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try #require(context.makeImage())
    }

    @Test func identicalImagesHashEquallyAndOppositesDiffer() throws {
        let black = try image(inverted: false)
        let blackAgain = try image(inverted: false)
        let white = try image(inverted: true)

        let a = try #require(SimilarPhotoFinder.differenceHash(black))
        let b = try #require(SimilarPhotoFinder.differenceHash(blackAgain))
        let c = try #require(SimilarPhotoFinder.differenceHash(white))
        #expect(a == b)
        #expect(a != c)
    }

    @Test func imageExtensionsAreRecognized() {
        #expect(FileMetadataReader.isImage("/tmp/a.HEIC"))
        #expect(FileMetadataReader.isImage("/tmp/a.jpeg"))
        #expect(!FileMetadataReader.isImage("/tmp/a.dmg"))
        #expect(IgnoreRules.normalizeExtension(".DMG") == "dmg")
    }
}
