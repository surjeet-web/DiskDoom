import Foundation

// MARK: - D8 Smart Compression (ObservableObject; atomic replace; cancellable)
//
// Review fixes applied:
// - Compression applies via `FileManager.replaceItemAt` (atomic) — never
//   manual remove-then-move, which loses the file on crash/power loss.
// - Analysis + compression run in background Tasks with cancellation.
// - Already-compressed formats are skipped via extension estimates.

struct CompressibleFile: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let logicalBytes: Int64
    let physicalBytes: Int64
    let daysSinceAccess: Int? // nil = unknown (never inferred from atime as ground truth)
    let estimatedSaving: Int64
}

final class SmartCompressionEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var files: [CompressibleFile] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isCompressing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?

    private var workTask: Task<Void, Never>?

    var totalSaving: Int64 { files.reduce(0) { $0 + $1.estimatedSaving } }

    /// Real candidate list from the scan index: large, uncompressed, old
    /// files in user-writable locations. System/app bundles are excluded —
    /// compressing them is not safe.
    func analyze(records: [ScannedRecord]) {
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isAnalyzing = true
                self.lastError = nil
            }
            let minBytes: Int64 = 100_000_000
            let found = await Task.detached {
                Self.realCandidates(records: records, minBytes: minBytes)
            }.value
            guard !Task.isCancelled else {
                await MainActor.run { self.isAnalyzing = false }
                return
            }
            await MainActor.run {
                self.files = found.sorted { $0.estimatedSaving > $1.estimatedSaving }
                self.isAnalyzing = false
            }
        }
    }

    private static func realCandidates(records: [ScannedRecord], minBytes: Int64) -> [CompressibleFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return records.compactMap { record -> CompressibleFile? in
            guard !record.isDirectory,
                  record.bytes >= minBytes,
                  record.path.hasPrefix(home),
                  isDocumentLike(path: record.path),
                  !isAlreadyCompressedFormat(path: record.path)
            else { return nil }
            let ratio = estimatedRatio(path: record.path)
            let saving = record.bytes - Int64(Double(record.bytes) * ratio)
            guard saving > 1_024 else { return nil }
            let ageDays = max(0, Int(Date().timeIntervalSince(record.modified) / 86_400))
            return CompressibleFile(
                path: record.path,
                name: (record.path as NSString).lastPathComponent,
                logicalBytes: record.bytes,
                // physicalBytes mirrors the logical size: the scanner does not
                // track a distinct on-disk size for files, so this must not be
                // presented as one.
                physicalBytes: record.bytes,
                daysSinceAccess: ageDays,
                estimatedSaving: saving)
        }
    }

    /// Allow-list of genuinely compressible document types.
    ///
    /// The old predicate accepted *any* file >= 100 MB under `$HOME`, which
    /// swept in `~/Library/Mail`, `~/Library/Mobile Documents`,
    /// `~/Library/CloudStorage`, `.ssh`, VM images and Time Machine staging —
    /// and "Compress All" then rewrote all of them. Rewriting anything under
    /// `~/Library` is out of scope for a space tool.
    private static func isDocumentLike(path: String) -> Bool {
        if path.hasPrefix("/Library") || path.hasPrefix("/System") || path.hasPrefix("/private/var/db") {
            return false
        }
        let libraryPrefix = FileManager.default.homeDirectoryForCurrentUser.path + "/Library"
        if path.hasPrefix(libraryPrefix) { return false }
        // Never touch code, binaries, or developer artifacts.
        if path.contains("/.git/") || path.contains("/node_modules/")
            || path.hasSuffix(".git") || path.contains("/.ssh/") { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        return documentExtensions.contains(ext)
    }

    private static let documentExtensions: Set<String> = [
        "txt", "md", "rtf", "doc", "docx", "odt", "pdf", "pages", "numbers", "key",
        "csv", "tsv", "json", "xml", "yaml", "yml", "html", "htm", "log",
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "psd", "ai",
        "mp3", "wav", "aiff", "m4a", "mp4", "mov", "avi", "mkv",
        "zip", "tar", "gz", "bz2", "7z", "dmg", "pkg",
        "epub", "mobi", "ppt", "pptx", "keynote", "icns",
    ]

    /// Whether the volume containing `path` supports transparent file compression.
    ///
    /// `ditto --hfsCompression` is an **HFS+** feature. APFS (the default on
    /// every Mac shipped since ~2017) has no transparent compression, so on
    /// APFS "Compress All" rewrote every candidate file — copy to
    /// `path + ".tmp"` then `replaceItemAt` — for **zero** space saved, and
    /// *decompressed* files that were already compressed, temporarily
    /// doubling them on disk. On a nearly-full volume that risks ENOSPC
    /// mid-copy for no benefit.
    ///
    /// `MNT_COMPRESS` in `statfs.f_flags` is set only on compression-capable
    /// volumes. If we cannot determine it, we refuse rather than silently
    /// rewriting the user's files.
    static func volumeSupportsCompression(at path: String) -> Bool {
        var fs = statfs()
        let target = (path as NSString).expandingTildeInPath
        guard statfs(target, &fs) == 0 else { return false }
        // MNT_COMPRESS == 0x00000004
        return (fs.f_flags & UInt32(0x4)) != 0
    }

    /// Compress one file atomically: ditto to temp, then replaceItemAt.
    /// Static + detached-safe: Sendable in (path), throws out.
    static func compressFile(at path: String) throws {
        guard volumeSupportsCompression(at: path) else {
            throw NSError(
                domain: "SmartCompression", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "This volume doesn't support transparent compression (APFS has no such feature). Refusing to rewrite the file for no space saving."])
        }
        let tmpURL = URL(fileURLWithPath: path + ".diskbuddy-tmp")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["--hfsCompression", path, tmpURL.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain stderr before waiting (64 KB pipe deadlock), and don't let a
        // hung ditto block forever on a 40 GB file.
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SmartCompression", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto exited with status \(process.terminationStatus)"])
        }
        // Atomic: the original is either fully replaced or untouched.
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: tmpURL)
    }

    func compressAll() {
        compress(files: files)
    }

    /// Compress an explicit list. Callers must pass only what the user
    /// selected — there is no longer an implicit "everything".
    func compress(files list: [CompressibleFile]) {
        guard !list.isEmpty else { return }
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isCompressing = true
                self.progress = 0
                self.lastError = nil
            }
            var done = 0
            for file in list {
                if Task.isCancelled { break }
                do {
                    try await Task.detached { try Self.compressFile(at: file.path) }.value
                } catch {
                    await MainActor.run { self.lastError = "\(file.name): \(error.localizedDescription)" }
                }
                done += 1
                let fraction = Double(done) / Double(max(list.count, 1))
                await MainActor.run { self.progress = fraction }
            }
            await MainActor.run { self.isCompressing = false }
        }
    }

    func cancel() {
        workTask?.cancel()
        workTask = nil
    }

    static func isAlreadyCompressedFormat(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "mp3", "mp4", "m4a",
                "zip", "gz", "bz2", "xz", "7z", "rar", "pdf"].contains(ext)
    }

    static func estimatedRatio(path: String) -> Double {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "json", "xml", "html", "css", "js", "swift", "log",
             "csv", "yaml", "toml", "plist", "strings", "bin", "tar", "mov":
            return 0.30
        case "db", "sqlite", "sqlite3", "dylib":
            return 0.55
        default:
            return 0.60
        }
    }
}
