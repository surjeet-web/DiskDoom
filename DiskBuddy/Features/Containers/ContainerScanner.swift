import Foundation
import AppKit

// MARK: - D9 Container Isolation View scanner (background, depth-limited, cancellable)
//
// Review fixes applied: runs in a detached background Task with cancellation
// checks (never blocks the caller's actor), recursion depth is capped, and
// per-directory sizes come from a bounded walk — cost is O(files under
// ~/Library/Containers), typically 1–3s.

struct SandboxContainer: Identifiable {
    let id = UUID()
    let bundleID: String
    let appName: String
    let totalBytes: Int64
    let topItems: [(name: String, bytes: Int64, kind: ItemKind)]

    enum ItemKind: String {
        case cache, preferences, savedState, tmp, data, other
    }
}

final class ContainerScanner: ObservableObject, @unchecked Sendable {
    @Published private(set) var containers: [SandboxContainer] = []
    @Published private(set) var isScanning = false
    private var task: Task<Void, Never>?
    /// Explicit flag the detached walk actually reads — `Task.isCancelled`
    /// inside `Task.detached` is always false, so cancel did nothing before.
    private var token = ScanCancellation()
    private let stateLock = NSLock()
    private var walkInFlight = false

    /// Wall-clock budget: the launch fan-out starts ~8 walks at once and this
    /// one must not be the reason the main scan misses its 240s deadline.
    private static let totalBudget: TimeInterval = 30

    var totalBytes: Int64 { containers.reduce(0) { $0 + $1.totalBytes } }

    func scan() {
        // Synchronous guard — `isScanning` is published asynchronously, so two
        // quick taps previously launched two full ~/Library/Containers walks.
        let alreadyRunning = stateLock.withLock { () -> Bool in
            guard !walkInFlight else { return true }
            walkInFlight = true
            return false
        }
        guard !alreadyRunning else { return }

        task?.cancel()
        token.cancel()
        let token = ScanCancellation()
        self.token = token
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isScanning = true }
            // Bounded walk runs detached (never on the caller's actor); the
            // token below is the cooperative flag that same detached task reads.
            let found = await Task.detached {
                Self.scanSync(token: token)
            }.value
            guard !token.isCancelled else {
                await MainActor.run {
                    self.isScanning = false
                    self.stateLock.withLock { self.walkInFlight = false }
                }
                return
            }
            await MainActor.run {
                self.containers = found
                self.isScanning = false
                self.stateLock.withLock { self.walkInFlight = false }
            }
        }
    }

    func cancel() {
        token.cancel()
        task?.cancel()
        task = nil
    }

    private static func scanSync(token: ScanCancellation) -> [SandboxContainer] {
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(totalBudget)
        let containersURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers", isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: containersURL.path) else { return [] }
        var results: [SandboxContainer] = []
        for name in names {
            if token.isCancelled { break }
            if Date() >= deadline { break }
            let dirURL = containersURL.appendingPathComponent(name, isDirectory: true)
            let size = directoryBytes(at: dirURL, maxDepth: 4, deadline: deadline, isCancelled: { token.isCancelled })
            guard size > 0 else { continue }
            let top = topLevelItems(at: dirURL, deadline: deadline, isCancelled: { token.isCancelled })
            let appName: String
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
                appName = appURL.deletingPathExtension().lastPathComponent
            } else {
                appName = name
            }
            results.append(SandboxContainer(bundleID: name, appName: appName, totalBytes: size, topItems: top))
        }
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Bounded recursive size walk (depth-capped, time-capped, cancellation-checked).
    private static func directoryBytes(at url: URL, maxDepth: Int, deadline: Date, isCancelled: () -> Bool) -> Int64 {
        guard maxDepth >= 0, !isCancelled() else { return 0 }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return 0 }
        var total: Int64 = 0
        for child in children {
            if isCancelled() { break }
            if Date() >= deadline { break }
            let values = try? child.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true {
                total += directoryBytes(at: child, maxDepth: maxDepth - 1, deadline: deadline, isCancelled: isCancelled)
            } else {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private static func topLevelItems(at url: URL, deadline: Date, isCancelled: () -> Bool) -> [(name: String, bytes: Int64, kind: SandboxContainer.ItemKind)] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }
        return children.prefix(8).map { child in
            let name = child.lastPathComponent
            let lower = child.path.lowercased()
            let kind: SandboxContainer.ItemKind
            if lower.contains("/cache") { kind = .cache }
            else if lower.contains("preferences") { kind = .preferences }
            else if lower.contains("saved application state") { kind = .savedState }
            else if lower.hasSuffix("/tmp") { kind = .tmp }
            else if lower.contains("/data") { kind = .data }
            else { kind = .other }
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bytes: Int64 = isDir
                // Previously hardcoded `isCancelled: { false }`, so this subtree
                // walk could not be stopped at all. It now honours the caller's
                // token and the shared deadline.
                ? directoryBytes(at: child, maxDepth: 2, deadline: deadline, isCancelled: isCancelled)
                : Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            return (name, bytes, kind)
        }
        .sorted { $0.bytes > $1.bytes }
    }
}
