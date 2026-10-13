import Foundation

/// Small, Sendable snapshot of installed apps; no icons or mutable scanner state
/// cross from the main actor into the search worker.
struct SearchableApp: Sendable {
    let name: String
    let bundleID: String
    let path: String
    let bytes: Int64
}

struct GlobalSearchHit: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case section, visualization, application, folder, file
    }

    let kind: Kind
    let title: String
    let detail: String
    let target: String
    let bytes: Int64?
    let category: NodeCategory?
    let score: Int

    var id: String { kind.rawValue + ":" + target }
}

struct GlobalSearchResult: Sendable {
    let hits: [GlobalSearchHit]
    let matches: Int
    let indexedFiles: Int

    static let empty = GlobalSearchResult(hits: [], matches: 0, indexedFiles: 0)
}

/// Bounded best-match search. No filesystem traversal or full-index sort occurs
/// while typing; only already-indexed scan data is considered.
enum GlobalSearch {
    static let maxResults = 80

    static func find(
        query rawQuery: String,
        records: [ScannedRecord],
        root: ScanNode?,
        apps: [SearchableApp],
        sections: [(id: String, title: String)],
        visualizations: [(id: String, title: String)]
    ) -> GlobalSearchResult {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }
        var best: [GlobalSearchHit] = []
        var matches = 0
        var indexedFiles = 0
        var seenFolders = Set<String>()

        func offer(_ kind: GlobalSearchHit.Kind, title: String, detail: String,
                   target: String, bytes: Int64? = nil, category: NodeCategory? = nil,
                   name: String, path: String = "") {
            let score: Int
            if name.localizedCaseInsensitiveCompare(query) == .orderedSame {
                score = 0
            } else if name.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
                score = 1
            } else if name.localizedStandardContains(query) {
                score = 2
            } else if query.count >= 3 && path.localizedStandardContains(query) {
                score = 3
            } else {
                return
            }
            if kind == .folder && !seenFolders.insert(target).inserted { return }
            matches += 1
            let hit = GlobalSearchHit(kind: kind, title: title, detail: detail,
                                      target: target, bytes: bytes, category: category, score: score)
            if best.count == maxResults, let last = best.last, !preferred(hit, last) { return }
            let position = best.firstIndex(where: { preferred(hit, $0) }) ?? best.endIndex
            best.insert(hit, at: position)
            if best.count > maxResults { best.removeLast() }
        }

        for section in sections {
            offer(.section, title: section.title, detail: "Go to section", target: section.id, name: section.title)
        }
        for view in visualizations {
            offer(.visualization, title: view.title, detail: "Open Explore view", target: view.id, name: view.title)
        }
        for app in apps {
            if Task.isCancelled { return .empty }
            offer(.application, title: app.name, detail: app.bundleID, target: app.path,
                  bytes: app.bytes, name: app.name, path: app.bundleID)
        }

        // Traverse only nodes that represent folders/collapsed packages. Flat
        // records supply files and empty directories without duplicating nodes.
        if query.count >= 2, let root {
            var pending = [root]
            while let node = pending.popLast() {
                if Task.isCancelled { return .empty }
                if node.isActionable && (!node.children.isEmpty || node.isCollapsed) {
                    offer(.folder, title: node.name, detail: node.path, target: node.path,
                          bytes: node.sizeBytes, category: node.category, name: node.name, path: node.path)
                }
                pending.append(contentsOf: node.children)
            }
        }

        // One-character queries are useful for sections/apps, but an enormous
        // number of file hits makes them noisy and expensive; require two.
        if query.count >= 2 {
            for (index, record) in records.enumerated() {
                if index & 1023 == 0 && Task.isCancelled { return .empty }
                if record.isDirectory {
                    offer(.folder, title: (record.path as NSString).lastPathComponent,
                          detail: record.path, target: record.path, bytes: record.bytes,
                          category: record.category, name: (record.path as NSString).lastPathComponent, path: record.path)
                } else {
                    indexedFiles += 1
                    let name = (record.path as NSString).lastPathComponent
                    offer(.file, title: name, detail: record.path, target: record.path,
                          bytes: record.bytes, category: record.category, name: name, path: record.path)
                }
            }
        }
        return GlobalSearchResult(hits: best, matches: matches, indexedFiles: indexedFiles)
    }

    private static func preferred(_ lhs: GlobalSearchHit, _ rhs: GlobalSearchHit) -> Bool {
        if lhs.score != rhs.score { return lhs.score < rhs.score }
        if lhs.kind != rhs.kind { return rank(lhs.kind) < rank(rhs.kind) }
        if lhs.bytes != rhs.bytes { return (lhs.bytes ?? 0) > (rhs.bytes ?? 0) }
        return lhs.target < rhs.target
    }

    private static func rank(_ kind: GlobalSearchHit.Kind) -> Int {
        switch kind {
        case .section: return 0
        case .visualization: return 1
        case .application: return 2
        case .folder: return 3
        case .file: return 4
        }
    }
}
