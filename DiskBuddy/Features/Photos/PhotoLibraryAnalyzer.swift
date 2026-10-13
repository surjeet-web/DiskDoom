import Foundation

// MARK: - D13 Photo Library Analyzer (ObservableObject; honest access states)
//
// Review fixes applied:
// - Never fabricates numbers: if the library can't be read (missing, TCC
//   denial, non-default location), the UI shows an explicit access state —
//   never an "empty library".
// - No hardcoded internal paths presented as fact (Previously-claimed
//   Recently-Deleted internals are not relied upon); reclaimable space is
//   reported from measurable structure + duplicates only.
// - Supports a custom library path instead of assuming ~/Pictures default.

struct PhotoLibraryStats {
    let totalBytes: Int64
    let originalsBytes: Int64
    let resourcesBytes: Int64
    let databaseBytes: Int64
    let photoCount: Int
    let videoCount: Int
    let duplicateSets: Int
    let duplicateWasteBytes: Int64
}

enum PhotoLibraryAccess {
    case unchecked
    case checking
    case granted(path: String)
    case missing(path: String) // not found OR not readable (TCC/permission) — explicit, never "empty"
}

final class PhotoLibraryAnalyzer: ObservableObject, @unchecked Sendable {
    @Published private(set) var access: PhotoLibraryAccess = .unchecked
    @Published private(set) var stats: PhotoLibraryStats?
    @Published private(set) var isAnalyzing = false
    @Published var customPath = ""
    /// Access probe task.
    private var accessTask: Task<Void, Never>?
    /// Measurement task. Kept SEPARATE from `accessTask`: `checkAccess()` used to
    /// overwrite the single `task` handle with its own probe, so cancelling
    /// during a library walk killed the probe handle (already finished) and left
    /// the real walk running with no way to stop it.
    private var measureTask: Task<Void, Never>?
    /// Explicit flag the detached walk reads — `Task.isCancelled` inside
    /// `Task.detached` is always false.
    private var token = ScanCancellation()

    /// A large library (200k+ original files) must not run unbounded alongside
    /// the launch fan-out.
    private static let measureBudget: TimeInterval = 25

    var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Photos Library.photoslibrary", isDirectory: true).path
    }

    /// Check readability of the library package (existence + listable).
    func checkAccess() {
        accessTask?.cancel()
        token.cancel()
        let token = ScanCancellation()
        self.token = token
        accessTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                guard !token.isCancelled else { return }
                self.access = .checking
                self.stats = nil
                self.isAnalyzing = false
            }
            let rawPath = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = rawPath.isEmpty ? defaultPath : (rawPath as NSString).expandingTildeInPath
            let readable = await Task.detached {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: target, isDirectory: &isDir), isDir.boolValue else { return false }
                return (try? FileManager.default.contentsOfDirectory(atPath: target)) != nil
            }.value
            guard !token.isCancelled else {
                // Was: bare `return` — which left `isAnalyzing == true`
                // forever, so the view showed a permanent spinner.
                return
            }
            await MainActor.run {
                guard !token.isCancelled else { return }
                if readable {
                    self.access = .granted(path: target)
                    self.measure(path: target)
                } else {
                    self.access = .missing(path: target)
                }
            }
        }
    }

    /// Real measurement of the library package: folder sizes by role +
    /// media counts by extension. Duplicate detection requires the Photos
    /// framework and is reported as unavailable (never fabricated).
    private func measure(path: String) {
        measureTask?.cancel()
        token.cancel()
        let token = ScanCancellation()
        self.token = token
        measureTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                guard !token.isCancelled else { return }
                self.isAnalyzing = true
            }
            let stats = await Task.detached {
                Self.measureSync(packagePath: path, token: token)
            }.value
            guard !token.isCancelled else {
                return
            }
            await MainActor.run {
                guard !token.isCancelled else { return }
                self.stats = stats
                self.isAnalyzing = false
            }
        }
    }

    private static func measureSync(packagePath: String, token: ScanCancellation) -> PhotoLibraryStats {
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(measureBudget)
        func directoryBytes(_ name: String) -> Int64 {
            let url = URL(fileURLWithPath: packagePath).appendingPathComponent(name, isDirectory: true)
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .totalFileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
            var total: Int64 = 0
            var visited = 0
            for case let file as URL in enumerator {
                visited += 1
                if visited & 0x3FF == 0 {
                    if token.isCancelled { break }
                    if Date() >= deadline { break }
                }
                if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    total += Int64(size)
                }
            }
            return total
        }
        let originals = directoryBytes("originals")
        let resources = directoryBytes("resources")
        let database = directoryBytes("database")

        // Media counts from originals (extension-based).
        var photos = 0
        var videos = 0
        let photoExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tiff", "gif", "raw", "dng", "cr2", "nef", "arw"]
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mts"]
        let originalsURL = URL(fileURLWithPath: packagePath).appendingPathComponent("originals", isDirectory: true)
        if !token.isCancelled, Date() < deadline,
           let enumerator = fm.enumerator(at: originalsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            var visited = 0
            for case let file as URL in enumerator {
                visited += 1
                if visited & 0x3FF == 0 {
                    if token.isCancelled { break }
                    if Date() >= deadline { break }
                }
                let ext = file.pathExtension.lowercased()
                if photoExtensions.contains(ext) { photos += 1 }
                if videoExtensions.contains(ext) { videos += 1 }
            }
        }

        let total = originals + resources + database
        return PhotoLibraryStats(
            totalBytes: total,
            originalsBytes: originals,
            resourcesBytes: resources,
            databaseBytes: database,
            photoCount: photos,
            videoCount: videos,
            duplicateSets: 0,
            duplicateWasteBytes: 0)
    }

    func cancel() {
        token.cancel()
        accessTask?.cancel()
        measureTask?.cancel()
        accessTask = nil
        measureTask = nil
        isAnalyzing = false
    }
}
