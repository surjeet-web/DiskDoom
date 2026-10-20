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
    /// Threshold of the last completed run — lets views avoid re-hashing
    /// the same data on every tab visit.
    @Published private(set) var lastRunMinBytes: Int64 = -1
    @Published private(set) var lastRunScanID: UUID?
    @Published private(set) var lastRunRecordCount = -1
    private var task: Task<Void, Never>?
    @MainActor private var runID = UUID()

    @MainActor
    func find(in records: [ScannedRecord], minBytes: Int64, scanID: UUID? = nil) {
        task?.cancel()
        let id = UUID()
        runID = id
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                guard self.runID == id else { return }
                self.isRunning = true; self.sets = []; self.progress = 0
            }
            let found = await PerformanceMonitor.measure("DuplicateFinder.hash", threshold: 5) {
                await Self.findAsync(records: records, minBytes: minBytes) { fraction in
                    await MainActor.run {
                        guard self.runID == id else { return }
                        self.progress = fraction
                    }
                }
            }
            PerformanceMonitor.checkMemory(label: "DuplicateFinder after hashing")
            guard !Task.isCancelled else {
                await MainActor.run {
                    guard self.runID == id else { return }
                    self.isRunning = false
                }
                return
            }
            await MainActor.run {
                guard self.runID == id else { return }
                self.sets = found
                self.isRunning = false
                self.progress = 1
                self.lastRunMinBytes = minBytes
                self.lastRunScanID = scanID
                self.lastRunRecordCount = records.count
            }
        }
    }

    @MainActor
    func cancel() {
        runID = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Reusable, UI-free entry point for the duplicate monitor and tests.
    nonisolated static func findSets(records: [ScannedRecord], minBytes: Int64) async -> [DuplicateSet] {
        await findAsync(records: records, minBytes: minBytes) { _ in }
    }

    /// Async pipeline with hash-cache consult: full SHA-256 hits are keyed by
    /// path + size + mtime, so second scans skip unchanged files (10–50x).
    /// Unchanged files keep their cache rows; replaced files miss and re-hash
    /// (REPLACE on store lazily evicts the stale row).
    private static func findAsync(
        records: [ScannedRecord],
        minBytes: Int64,
        report: @Sendable (Double) async -> Void
    ) async -> [DuplicateSet] {
        // Stage 1: size buckets (different sizes can't be duplicates).
        var buckets: [Int64: [ScannedRecord]] = [:]
        for record in records where !record.isDirectory && record.bytes >= minBytes {
            if Task.isCancelled { return [] }
            buckets[record.bytes, default: []].append(record)
        }
        var sets: [DuplicateSet] = []
        var hashed = 0
        var cacheHits = 0
        let totalCandidates = buckets.values.filter { $0.count >= 2 }.reduce(0) { $0 + $1.count }
        for (_, group) in buckets {
            if Task.isCancelled { return [] }
            guard group.count >= 2 else { continue }
            // Stage 2: 8KB sample hash (cheap, in-memory only).
            var sampleGroups: [String: [ScannedRecord]] = [:]
            for record in group {
                if Task.isCancelled { return [] }
                if let hash = sampleHash(path: record.path) {
                    sampleGroups[hash, default: []].append(record)
                }
            }
            for (_, candidates) in sampleGroups where candidates.count >= 2 {
                // Stage 3: full SHA-256, cache-consulted.
                var fullGroups: [String: [ScannedRecord]] = [:]
                for record in candidates {
                    if Task.isCancelled { return [] }
                    if let cached = try? await ScanDatabase.shared.cachedHash(
                        path: record.path, size: record.bytes, mtime: record.modified) {
                        fullGroups[cached, default: []].append(record)
                        cacheHits += 1
                    } else if let hash = fullHash(path: record.path) {
                        fullGroups[hash, default: []].append(record)
                        try? await ScanDatabase.shared.storeHash(
                            path: record.path, size: record.bytes,
                            mtime: record.modified, sha256: hash)
                    }
                    hashed += 1
                    if hashed % 25 == 0, totalCandidates > 0 {
                        await report(0.1 + 0.8 * Double(hashed) / Double(totalCandidates))
                    }
                }
                for (hash, files) in fullGroups where files.count >= 2 {
                    sets.append(DuplicateSet(
                        hashPrefix: "sha256: \(hash.prefix(6))…\(hash.suffix(2))",
                        files: files.map { DuplicateFile(path: $0.path, bytes: $0.bytes) }))
                }
            }
        }
        _ = cacheHits
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
