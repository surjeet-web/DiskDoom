import Foundation
import Testing
@testable import DiskDoom

struct DuplicateExploreUXTests {
    @Test func suggestedKeepIsStableAndPrefersDocuments() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let downloads = DuplicateFile(path: home + "/Downloads/copy.jpg", bytes: 42)
        let documents = DuplicateFile(path: home + "/Documents/original.jpg", bytes: 42)
        let first = DuplicateSet(hashPrefix: "sha256: abc", files: [downloads, documents])
        let rescanned = DuplicateSet(hashPrefix: "sha256: abc", files: [documents, downloads])

        #expect(first.id == rescanned.id)
        #expect(first.files[0].id == rescanned.files[1].id)
        #expect(first.suggestedKeep?.path == documents.path)
        #expect(first.keptFile(selectedID: downloads.id)?.path == downloads.path)
        #expect(first.keptFile(selectedID: UUID())?.path == documents.path)
        let changedMembership = DuplicateSet(hashPrefix: "sha256: abc", files: [documents])
        #expect(first.id != changedMembership.id)
    }

    @Test @MainActor func unknownAndFutureDatesDoNotReadAsOld() throws {
        let state = AppState()
        let now = Date()
        state.records = [
            ScannedRecord(path: "/tmp/unknown", bytes: 10, physical: 10,
                          modified: .distantPast, isDirectory: false, category: .other),
            ScannedRecord(path: "/tmp/future", bytes: 20, physical: 20,
                          modified: now.addingTimeInterval(86_400), isDirectory: false, category: .other)
        ]
        let unknown = try #require(state.ageBuckets.last)
        #expect(unknown.label == "Unknown date")
        #expect(unknown.id == state.ageBuckets.last?.id)
        #expect(unknown.files == 2)
        #expect(unknown.bytes == 30)
        #expect(state.ageBuckets[7].files == 0)
    }

    @Test @MainActor func focusedChartUsesExpandedNodeFromLiveTree() {
        let state = AppState()
        let old = ScanNode(name: "Caches", path: "/scan/Caches", sizeBytes: 80,
                           category: .other, fileCount: 2, isCollapsed: true)
        state.scanRoot = ScanNode(name: "Scan", path: "/scan", sizeBytes: 80,
                                  category: .other, fileCount: 2, children: [old])
        #expect(state.currentScanNode(path: old.path)?.isCollapsed == true)

        let expanded = ScanNode(name: "Caches", path: old.path, sizeBytes: 80,
                                category: .other, fileCount: 2, children: [
                                    ScanNode(name: "Build", path: "/scan/Caches/Build",
                                             sizeBytes: 80, category: .other, fileCount: 2)
                                ])
        state.scanRoot = ScanNode(name: "Scan", path: "/scan", sizeBytes: 80,
                                  category: .other, fileCount: 2, children: [expanded])
        #expect(state.currentScanNode(path: old.path)?.children.first?.name == "Build")
        #expect(state.currentScanNode(path: "/scan/Caches/Build")?.name == "Build")
        #expect(state.currentScanNode(path: "/scan/Caches/Unknown") == nil)
        #expect(state.currentScanNode(path: "/scan/Caches2") == nil)
    }
}
