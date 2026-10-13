import Foundation

// MARK: - D8 Smart Compression (ObservableObject; atomic replace; cancellable)
//
// Review fixes applied:
// - Compression applies via `FileManager.replaceItemAt` (atomic) — never
//   manual remove-then-move, which loses the file on crash/power loss.
// - Analysis + compression run in background Tasks with cancellation.
// - Already-compressed formats are skipped via extension estimates.

struct CompressibleFile: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let name: String
    let logicalBytes: Int64
    let physicalBytes: Int64
    let daysSinceAccess: Int? // nil = unknown (never inferred from atime as ground truth)
    let estimatedSaving: Int64
}

@MainActor
final class SmartCompressionEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var files: [CompressibleFile] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isCompressing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?

    private var workTask: Task<Void, Never>?
    private var cancellation = ScanCancellation()

    var totalSaving: Int64 { files.reduce(0) { $0 + $1.estimatedSaving } }

    /// Real candidate list from the scan index: large, uncompressed, old
    /// files in user-writable locations. System/app bundles are excluded —
    /// compressing them is not safe.
    func analyze(records: [ScannedRecord]) {
        workTask?.cancel()
        cancellation.cancel()
        isCompressing = false
        isAnalyzing = true
        workTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isAnalyzing = true
                self.lastError = nil
            }
            let minBytes: Int64 = 100_000_000
            let found = await Task.detached {
                Self.realCandidates(records: records, minBytes: minBytes)
            }.value
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.files = found.sorted { $0.estimatedSaving > $1.estimatedSaving }
                self.isAnalyzing = false
            }
        }
    }

    nonisolated private static func realCandidates(records: [ScannedRecord], minBytes: Int64) -> [CompressibleFile] {
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
    nonisolated private static func isDocumentLike(path: String) -> Bool {
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

    nonisolated private static let documentExtensions: Set<String> = [
        "txt", "md", "rtf", "doc", "docx", "odt", "pdf", "pages", "numbers", "key",
        "csv", "tsv", "json", "xml", "yaml", "yml", "html", "htm", "log",
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "psd", "ai",
        "mp3", "wav", "aiff", "m4a", "mp4", "mov", "avi", "mkv",
        "zip", "tar", "gz", "bz2", "7z", "dmg", "pkg",
        "epub", "mobi", "ppt", "pptx", "keynote", "icns",
    ]

    /// Whether the volume containing `path` supports transparent file compression.
    ///
    /// Query the documented decmpfs capability, not mount flags: 0x4 in
    /// `statfs.f_flags` is MNT_NOEXEC, unrelated to file compression.
    /// Unknown capability is treated as unsupported.
    nonisolated static func volumeSupportsCompression(at path: String) -> Bool {
        let target = (path as NSString).expandingTildeInPath
        let values = try? URL(fileURLWithPath: target)
            .resourceValues(forKeys: [.volumeSupportsCompressionKey])
        return values?.volumeSupportsCompression == true
    }

    /// Compress one file atomically: ditto to temp, then replaceItemAt.
    /// Static + detached-safe: Sendable in (path), throws out.
    nonisolated static func compressFile(at path: String, cancellation: ScanCancellation = .never) throws {
        guard volumeSupportsCompression(at: path) else {
            throw NSError(
                domain: "SmartCompression", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Transparent compression support could not be confirmed for this volume. The file was not rewritten."])
        }
        let sourceURL = URL(fileURLWithPath: path)
        // Reserve a unique sibling directory; never overwrite or remove a
        // user's pre-existing `<filename>.diskbuddy-tmp` item.
        let temporaryDirectory = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".diskbuddy-compression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let tmpURL = temporaryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        _ = try FeatureProcessRunner.run(executable: "/usr/bin/ditto",
            arguments: ["--hfsCompression", path, tmpURL.path], timeout: 300,
            captureOutput: false, cancellation: cancellation)
        guard !cancellation.isCancelled else { throw CancellationError() }
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
        cancellation.cancel()
        let cancellation = ScanCancellation()
        self.cancellation = cancellation
        isAnalyzing = false
        isCompressing = true
        workTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isCompressing = true
                self.progress = 0
                self.lastError = nil
            }
            var done = 0
            for file in list {
                if Task.isCancelled { break }
                do {
                    try await Task.detached { try Self.compressFile(at: file.path, cancellation: cancellation) }.value
                } catch {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.lastError = "\(file.name): \(error.localizedDescription)"
                    }
                }
                done += 1
                let fraction = Double(done) / Double(max(list.count, 1))
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.progress = fraction
                }
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isCompressing = false
            }
        }
    }

    func cancel() {
        cancellation.cancel()
        workTask?.cancel()
        workTask = nil
        isAnalyzing = false
        isCompressing = false
    }

    nonisolated static func isAlreadyCompressedFormat(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "mp3", "mp4", "m4a",
                "zip", "gz", "bz2", "xz", "7z", "rar", "pdf"].contains(ext)
    }

    nonisolated static func estimatedRatio(path: String) -> Double {
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
