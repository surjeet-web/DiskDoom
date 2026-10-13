import Foundation

// MARK: - Smart recommendations (57–59) + Large/Old finders (64–65), from real records

struct Recommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let bytes: Int64
    let confidence: Confidence
    let paths: [(path: String, bytes: Int64)]

    enum Confidence: String {
        case highlyRecommended, recommended, consider
    }

    /// Bytes the user can actually act on: only the listed `paths` are
    /// offered for staging. WHY: `bytes` covers the whole population, so a
    /// headline built from it promised space no button could free.
    var stageableBytes: Int64 { paths.reduce(0) { $0 + $1.bytes } }
}

final class RecommendationsEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var recommendations: [Recommendation] = []
    @Published private(set) var largeFiles: [ScannedRecord] = []
    @Published private(set) var oldFiles: [ScannedRecord] = []

    var largeThreshold: Int64 = 100_000_000
    var oldMonths = 6

    /// The view only ever renders this many rows, so anything beyond it is
    /// sorting work nobody sees. Previously the whole (up to 1M record) index
    /// was filtered 5× and fully sorted 2× on the main actor on every appear.
    private static let maxResults = 500

    func compute(records: [ScannedRecord]) {
        let cutoff = Date().addingTimeInterval(-Double(oldMonths) * 30 * 86_400)

        // ── Single pass over the index ──
        var large: [ScannedRecord] = []
        var old: [ScannedRecord] = []
        var stale: [ScannedRecord] = []
        var caches: [ScannedRecord] = []
        var logs: [ScannedRecord] = []
        var staleBytes: Int64 = 0
        var cacheBytes: Int64 = 0
        var logBytes: Int64 = 0

        for record in records where !record.isDirectory {
            let bytes = record.bytes
            let isOld = record.modified < cutoff
            if bytes >= largeThreshold { large.append(record) }
            if isOld { old.append(record) }
            switch record.category {
            case .stale: stale.append(record); staleBytes += bytes
            case .caches: caches.append(record); cacheBytes += bytes
            case .logs where isOld: logs.append(record); logBytes += bytes
            default: break
            }
        }

        // ── One bounded sort (descending by size) per result list ──
        large.sort { $0.bytes > $1.bytes }
        old.sort { $0.bytes > $1.bytes }
        stale.sort { $0.bytes > $1.bytes }
        logs.sort { $0.bytes > $1.bytes }
        largeFiles = Array(large.prefix(Self.maxResults))
        oldFiles = Array(old.prefix(Self.maxResults))

        var recs: [Recommendation] = []
        // Stale artifacts first (safest).
        if !stale.isEmpty {
            recs.append(Recommendation(
                title: "Remove stale files from uninstalled apps",
                // WHY: "can never be used again" asserted something nobody
                // verified — these files belong to apps that are no longer
                // installed here, so they are *normally* safe to remove, but
                // the user should check before staging them.
                detail: "\(stale.count.formatted()) files left behind by apps that are no longer installed — normally safe to remove, but verify first.",
                bytes: staleBytes,
                confidence: .highlyRecommended,
                paths: Self.topPaths(stale, limit: 50)))
        }
        // Big caches.
        if !caches.isEmpty {
            caches.sort { $0.bytes > $1.bytes }
            recs.append(Recommendation(
                title: "Clean large app caches",
                detail: "Many caches regenerate, but removing them may sign you out or make apps rebuild data. Review the paths first.",
                bytes: cacheBytes,
                confidence: .highlyRecommended,
                paths: Self.topPaths(caches, limit: 100)))
        }
        // Old logs.
        if !logs.isEmpty {
            recs.append(Recommendation(
                title: "Clear old log files",
                detail: "Logs older than \(oldMonths) months may still be useful for troubleshooting. Review before removing.",
                bytes: logBytes,
                confidence: .recommended,
                paths: Self.topPaths(logs, limit: 50)))
        }
        // Forgotten large files (old AND large).
        let forgotten = old.filter { $0.bytes >= largeThreshold }
        if !forgotten.isEmpty {
            recs.append(Recommendation(
                title: "Review forgotten large files",
                detail: "Large files untouched for \(oldMonths)+ months — review before staging.",
                bytes: forgotten.prefix(20).reduce(0) { $0 + $1.bytes },
                confidence: .consider,
                paths: forgotten.prefix(20).map { ($0.path, $0.bytes) }))
        }
        recommendations = recs
    }

    /// Largest `limit` (path, bytes) pairs. Input must already be sorted
    /// descending by size — this deliberately does not re-sort.
    private static func topPaths(_ records: [ScannedRecord], limit: Int) -> [(path: String, bytes: Int64)] {
        records.prefix(limit).map { ($0.path, $0.bytes) }
    }

    /// Bytes the Quick Clean button can actually stage. WHY: each
    /// recommendation only lists its top paths, so summing `bytes` (the whole
    /// population) told the user they could free far more than the button
    /// would ever stage — the headline now matches the action.
    var quickCleanBytes: Int64 {
        highlyRecommended.reduce(0) { $0 + $1.stageableBytes }
    }

    /// The population the offered (top-N) paths were cut from, for an
    /// honest "X of Y total" next to the stageable figure.
    var quickCleanPopulationBytes: Int64 {
        highlyRecommended.reduce(0) { $0 + $1.bytes }
    }

    /// Files Quick Clean will actually stage (the shown/offered set).
    var quickCleanFileCount: Int {
        highlyRecommended.reduce(0) { $0 + $1.paths.count }
    }

    private var highlyRecommended: [Recommendation] {
        recommendations.filter { $0.confidence == .highlyRecommended }
    }
}
