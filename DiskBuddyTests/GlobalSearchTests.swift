import Foundation
import Testing
@testable import DiskDoom

struct GlobalSearchTests {
    @Test func searchesNavigationAppsAndIndexedFilesWithoutTouchingDisk() {
        let root = ScanNode(name: "Scan", path: "/indexed", sizeBytes: 50,
                            category: .userData, fileCount: 2, children: [
                                ScanNode(name: "Photos", path: "/indexed/Photos", sizeBytes: 40,
                                         category: .userData, fileCount: 2),
                                ScanNode(name: "Other (omitted)", path: "", sizeBytes: 10,
                                         category: .other, fileCount: 1, isSyntheticAggregate: true)
                            ])
        let records = [
            ScannedRecord(path: "/indexed/Photos", bytes: 40, physical: 40,
                          modified: .now, isDirectory: true, category: .userData),
            ScannedRecord(path: "/indexed/Photos/photo.jpg", bytes: 30, physical: 30,
                          modified: .now, isDirectory: false, category: .userData)
        ]
        let found = GlobalSearch.find(query: "photo", records: records, root: root,
            apps: [SearchableApp(name: "Photoshop", bundleID: "com.example.photoshop",
                                 path: "/Applications/Photoshop.app", bytes: 100)],
            sections: [(id: "photos", title: "Photos")],
            visualizations: [(id: "treemap", title: "Treemap")])

        #expect(found.hits.contains { $0.kind == .section && $0.target == "photos" })
        #expect(found.hits.contains { $0.kind == .application && $0.title == "Photoshop" })
        #expect(found.hits.contains { $0.kind == .folder && $0.target == "/indexed/Photos" })
        #expect(found.hits.contains { $0.kind == .file && $0.target == "/indexed/Photos/photo.jpg" })
        #expect(found.hits.first { $0.kind == .file }?.category == .userData)
        #expect(found.hits.filter { $0.kind == .folder && $0.target == "/indexed/Photos" }.count == 1)
        #expect(found.indexedFiles == 1)
        #expect(found.hits.first?.kind == .section) // exact name wins over prefix and path.
    }

    @Test func shortQueriesAvoidFileIndexAndLargeResultsAreBounded() {
        let records = (0..<250).map { index in
            ScannedRecord(path: "/scan/report-\(index).txt", bytes: Int64(index), physical: Int64(index),
                          modified: .now, isDirectory: false, category: .userData)
        }
        let short = GlobalSearch.find(query: "r", records: records, root: nil,
                                      apps: [], sections: [], visualizations: [])
        #expect(short.indexedFiles == 0)
        #expect(short.hits.isEmpty)

        let full = GlobalSearch.find(query: "report", records: records, root: nil,
                                     apps: [], sections: [], visualizations: [])
        #expect(full.matches == 250)
        #expect(full.hits.count == GlobalSearch.maxResults)
        #expect(full.hits.first?.bytes == 249)
    }

    @Test func syntheticAggregatesAreNotSearchResults() {
        let root = ScanNode(name: "Root", path: "/scan", sizeBytes: 1,
                            category: .other, fileCount: 1, children: [
                                ScanNode(name: "Secret aggregate", path: "", sizeBytes: 1,
                                         category: .other, fileCount: 1, isSyntheticAggregate: true)
                            ])
        let result = GlobalSearch.find(query: "secret", records: [], root: root,
                                       apps: [], sections: [], visualizations: [])
        #expect(result.hits.isEmpty)
    }

    @Test func pathMatchesOnlyAfterThreeCharacters() {
        let file = ScannedRecord(path: "/indexed/Invoices/receipt.dat", bytes: 42, physical: 42,
                                 modified: .now, isDirectory: false, category: .userData)
        let short = GlobalSearch.find(query: "in", records: [file], root: nil,
                                      apps: [], sections: [], visualizations: [])
        let path = GlobalSearch.find(query: "Invoices", records: [file], root: nil,
                                     apps: [], sections: [], visualizations: [])
        #expect(short.hits.isEmpty)
        #expect(path.hits.first?.kind == .file)
        #expect(path.hits.first?.score == 3)
    }
}
