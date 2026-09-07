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
}

final class RecommendationsEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var recommendations: [Recommendation] = []
    @Published private(set) var largeFiles: [ScannedRecord] = []
    @Published private(set) var oldFiles: [ScannedRecord] = []

    var largeThreshold: Int64 = 100_000_000
    var oldMonths = 6

    func compute(records: [ScannedRecord]) {
        let files = records.filter { !$0.isDirectory }
        // Large files (64).
        largeFiles = files.filter { $0.bytes >= largeThreshold }.sorted { $0.bytes > $1.bytes }
        // Old files (65): unmodified for oldMonths+.
        let cutoff = Date().addingTimeInterval(-Double(oldMonths) * 30 * 86_400)
        oldFiles = files.filter { $0.modified < cutoff }.sorted { $0.bytes > $1.bytes }

        var recs: [Recommendation] = []
        // Stale artifacts first (safest).
        let stale = files.filter { $0.category == .stale }
        if !stale.isEmpty {
            recs.append(Recommendation(
                title: "Remove stale files from uninstalled apps",
                detail: "\(stale.count.formatted()) orphaned files can never be used again.",
                bytes: stale.reduce(0) { $0 + $1.bytes },
                confidence: .highlyRecommended,
                paths: stale.sorted { $0.bytes > $1.bytes }.prefix(50).map { ($0.path, $0.bytes) }))
        }
        // Big caches.
        let caches = files.filter { $0.category == .caches }.sorted { $0.bytes > $1.bytes }
        if !caches.isEmpty {
            recs.append(Recommendation(
                title: "Clean large app caches",
                detail: "Caches regenerate automatically; clearing never breaks apps.",
                bytes: caches.prefix(100).reduce(0) { $0 + $1.bytes },
                confidence: .highlyRecommended,
                paths: caches.prefix(100).map { ($0.path, $0.bytes) }))
        }
        // Old logs.
        let logs = files.filter { $0.category == .logs && $0.modified < cutoff }
        if !logs.isEmpty {
            recs.append(Recommendation(
                title: "Clear old log files",
                detail: "Logs older than \(oldMonths) months are diagnostic history only.",
                bytes: logs.reduce(0) { $0 + $1.bytes },
                confidence: .recommended,
                paths: logs.sorted { $0.bytes > $1.bytes }.prefix(50).map { ($0.path, $0.bytes) }))
        }
        // Forgotten large files.
        let forgotten = oldFiles.filter { $0.bytes >= largeThreshold }
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

    var quickCleanBytes: Int64 {
        recommendations.filter { $0.confidence == .highlyRecommended }.reduce(0) { $0 + $1.bytes }
    }
}
