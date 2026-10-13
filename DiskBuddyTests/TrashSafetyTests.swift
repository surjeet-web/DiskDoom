import Foundation
import Testing
@testable import DiskDoom

struct TrashSafetyTests {
    @Test(arguments: ["/Library/../System", "/System/", "/var/db", "/var/folders/example", "/private/var/folders/example"])
    func normalizedProtectedPathsAreRefused(path: String) {
        #expect(TrashService.deletionRefusal(for: path) != nil)
    }

    @Test func refusesHomeAndRelativePaths() {
        #expect(TrashService.deletionRefusal(for: FileManager.default.homeDirectoryForCurrentUser.path) != nil)
        #expect(TrashService.deletionRefusal(for: "relative/file") != nil)
    }

    @Test func refusesSystemSymlinkWithoutDeletingAnything() throws {
        let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let link = caches.appendingPathComponent("diskbuddy-protected-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))
        defer { try? FileManager.default.removeItem(at: link) }
        #expect(TrashService.deletionRefusal(for: link.path) != nil)
    }

    @Test func prefixChecksRespectDirectoryBoundaries() {
        #expect(TrashService.deletionRefusal(for: "/Library/LaunchAgentsBackup/example") == nil)
    }
}
