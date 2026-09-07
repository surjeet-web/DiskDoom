import Foundation
import CryptoKit

// MARK: - Real duplicate pipeline: size bucket → 8KB sample hash → full SHA-256
//
// Runs on real scan records. Cancellable via Task.checkCancellation.
// Chunked file reads so multi-GB files never load fully into memory.

final class DuplicateFinder: ObservableObject, @unchecked Sendable {
    @Published private(set) var progress: Double = 0
    @Published private(set) var sets: [DuplicateSet] = []
    @Published private(set) var isRunning = false
    private var task: Task<Void, Never>?

    func find(in records: [ScannedRecord], minBytes: Int64) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isRunning = true; self.sets = []; self.progress = 0 }
            let found = await Task.detached {
                Self.findSync(records: records, minBytes: minBytes)
            }.value
            guard !Task.isCancelled else {
                await MainActor.run { self.isRunning = false }
                return
            }
            await MainActor.run {
                self.sets = found
                self.isRunning = false
                self.progress = 1
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func findSync(records: [ScannedRecord], minBytes: Int64) -> [DuplicateSet] {
        // Stage 1: size buckets (different sizes can't be duplicates).
        var buckets: [Int64: [ScannedRecord]] = [:]
        for record in records where !record.isDirectory && record.bytes >= minBytes {
            if Task.isCancelled { return [] }
            buckets[record.bytes, default: []].append(record)
        }
        var sets: [DuplicateSet] = []
        var done = 0
        let total = buckets.count
        for (_, group) in buckets {
            if Task.isCancelled { return [] }
            done += 1
            guard group.count >= 2 else { continue }
            // Stage 2: 8KB sample hash.
            var sampleGroups: [String: [ScannedRecord]] = [:]
            for record in group {
                if Task.isCancelled { return [] }
                if let hash = sampleHash(path: record.path) {
                    sampleGroups[hash, default: []].append(record)
                }
            }
            for (_, candidates) in sampleGroups where candidates.count >= 2 {
                // Stage 3: full SHA-256.
                var fullGroups: [String: [ScannedRecord]] = [:]
                for record in candidates {
                    if Task.isCancelled { return [] }
                    if let hash = fullHash(path: record.path) {
                        fullGroups[hash, default: []].append(record)
                    }
                }
                for (hash, files) in fullGroups where files.count >= 2 {
                    sets.append(DuplicateSet(
                        hashPrefix: "sha256: \(hash.prefix(6))…\(hash.suffix(2))",
                        files: files.map { DuplicateFile(path: $0.path, bytes: $0.bytes) }))
                }
            }
            _ = (done, total)
        }
        return sets.sorted { $0.reclaimable > $1.reclaimable }
    }

    private static func sampleHash(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8192)
        guard !data.isEmpty else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            let chunk = handle.readData(ofLength: 1_048_576)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
