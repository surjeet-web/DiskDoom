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

    /// Mock candidate list (production: derived from real scan + stat blocks).
    func analyze() {
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isAnalyzing = true
                self.lastError = nil
            }
            let found = Self.mockCandidates()
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

    private static func mockCandidates() -> [CompressibleFile] {
        let mock: [(String, Int64, Double, Int?)] = [
            ("~/Library/Caches/com.adobe.CC/huge-render-cache.bin", 8_200_000_000, 0.30, 120),
            ("~/Library/Application Support/Spotify/PersistentCache", 3_400_000_000, 0.45, 60),
            ("~/Documents/archives/old-project-logs.tar", 1_800_000_000, 0.25, 400),
            ("~/Library/Logs/DiagnosticReports/old-crashes.log", 900_000_000, 0.25, 200),
            ("~/Movies/unused-screen-recordings.mov", 2_400_000_000, 0.98, 90),
        ]
        return mock.compactMap { (path, logical, ratio, days) -> CompressibleFile? in
            if Self.isAlreadyCompressedFormat(path: path) { return nil }
            let saving = logical - Int64(Double(logical) * ratio)
            guard saving > 1_024 else { return nil }
            return CompressibleFile(
                path: path, name: (path as NSString).lastPathComponent,
                logicalBytes: logical, physicalBytes: logical,
                daysSinceAccess: days, estimatedSaving: saving)
        }
    }

    /// Compress one file atomically: ditto to temp, then replaceItemAt.
    /// Static + detached-safe: Sendable in (path), throws out.
    static func compressFile(at path: String) throws {
        let tmpURL = URL(fileURLWithPath: path + ".diskbuddy-tmp")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["--hfsCompression", path, tmpURL.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SmartCompression", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto exited with status \(process.terminationStatus)"])
        }
        // Atomic: the original is either fully replaced or untouched.
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: tmpURL)
    }

    func compressAll() {
        workTask?.cancel()
        workTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isCompressing = true
                self.progress = 0
                self.lastError = nil
            }
            let list = files
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
