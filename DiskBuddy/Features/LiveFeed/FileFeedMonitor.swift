import Foundation

// MARK: - D10 Real-Time File Creation Feed (retained DispatchSources + diff attribution)
//
// Correctness notes (production-grade rules):
// - A directory-fd DispatchSource only says "something in this dir changed" —
//   it cannot name the file. So the source is used purely as a TRIGGER; on
//   fire we diff a filename→(mtime,size) snapshot to attribute the actual
//   changed files. We never present the watched directory's own path as an
//   event path.
// - Every DispatchSource is stored in `sources` for its whole lifetime and
//   explicitly cancelled in stop()/deinit (never a fire-and-forget local).
// - Snapshot state lives only on `workQueue` (serial); @Published mutations
//   hop to main. No shared-mutable-state races.

struct FileFeedEvent: Identifiable {
    let id = UUID()
    let date: Date
    let path: String
    let isCreated: Bool
    let attributedApp: String?

    var fileName: String { (path as NSString).lastPathComponent }
}

// Sendable weak box so @Sendable DispatchSource handlers never capture the
// non-Sendable monitor directly.
private final class WeakFileFeedMonitor: @unchecked Sendable {
    weak var value: FileFeedMonitor?
}

// Confinement contract (why @unchecked Sendable is honest):
// - `snapshots`, `dirtyPaths`, `drainScheduled`, `baselineReady` are touched
//   only on `stateQueue` (serial).
// - `events`, `isMonitoring`, `eventsPerMinute` are touched only on main.
// - `sources` is touched on start/stop (main, from UI) and deinit
//   (DispatchSource.cancel is thread-safe).
final class FileFeedMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var events: [FileFeedEvent] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var eventsPerMinute = 0

    private var sources: [DispatchSourceFileSystemObject] = []
    /// Slow main-actor tick that recomputes the 60 s event window. WHY: the
    /// rate used to be recomputed only when a new batch drained, so after
    /// file activity stopped the displayed "events/min" froze at its last
    /// non-zero value indefinitely. Recomputing on a timer makes it decay
    /// back to 0 — a real rolling window, not a stale high-water mark.
    private var rateTask: Task<Void, Never>?
    private static let rateTickInterval: UInt64 = 5_000_000_000 // 5s
    private let workQueue = DispatchQueue(label: "com.diskbuddy.filefeed", qos: .utility)
    /// Snapshot state is confined to `stateQueue`; never touched elsewhere.
    private let stateQueue = DispatchQueue(label: "com.diskbuddy.filefeed.state", qos: .utility)
    private var snapshots: [String: [String: FileMeta]] = [:]
    /// Paths whose directory changed but which haven't been re-scanned yet.
    /// A single `mkdir` of 500 files fires hundreds of vnode events; without
    /// coalescing each one re-`stat`ed the *entire* directory (thousands of
    /// `attributesOfItem` calls), which is what made the UI stutter on real
    /// hardware whenever a build tool dropped a batch of files.
    private var dirtyPaths: Set<String> = []
    private var drainScheduled = false
    private var baselineReady = false

    private struct FileMeta {
        let mtime: TimeInterval
        let size: Int64
    }

    /// Coalescing window for directory re-scans.
    private static let coalesceInterval: TimeInterval = 0.25
    /// Hard cap on entries snapshotted per directory — a huge ~/Downloads must
    /// not turn one coalesced drain into its own stat storm.
    private static let maxSnapshotEntries = 20_000

    let watchPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Caches",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/Logs",
            "\(home)/Downloads",
        ]
    }()

    init() {
        // No seed events: the feed only shows real observed activity.
    }

    func start() {
        guard sources.isEmpty else { return }
        // Baseline first so enabling monitoring doesn't flood with history.
        // WHY async: `snapshot(of:)` stats every entry in the directory; run
        // synchronously here it blocked the main thread for the whole of
        // ~/Library/Caches + ~/Downloads and froze the launch UI.
        stateQueue.async { [weak self] in
            guard let self else { return }
            for path in self.watchPaths {
                self.snapshots[path] = self.snapshot(of: path)
            }
            self.baselineReady = true
        }
        var started: [DispatchSourceFileSystemObject] = []
        let box = WeakFileFeedMonitor()
        box.value = self
        for path in watchPaths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend],
                queue: workQueue)
            source.setEventHandler { [box, path] in
                box.value?.handleDirectoryChange(path: path)
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            started.append(source) // retained for the whole session
        }
        sources = started
        let didStart = !started.isEmpty
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = didStart
        }
        startRateTicks()
    }

    func stop() {
        for source in sources { source.cancel() }
        sources.removeAll()
        stopRateTicks()
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = false
        }
    }

    deinit {
        for source in sources { source.cancel() }
        rateTask?.cancel()
    }

    // MARK: Rolling events/min window

    /// Starts the main-actor tick that keeps `eventsPerMinute` decaying.
    private func startRateTicks() {
        stopRateTicks()
        rateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.rateTickInterval)
                if Task.isCancelled { return }
                self?.recomputeEventsPerMinute()
            }
        }
    }

    private func stopRateTicks() {
        rateTask?.cancel()
        rateTask = nil
    }

    /// Count of events observed in the last 60 seconds. Called on main only
    /// (drain batches and the rate tick) so the window both rises and falls
    /// with real activity.
    private func recomputeEventsPerMinute() {
        eventsPerMinute = Self.rollingWindowCount(events: events)
    }

    /// Pure windowed count: how many `events` fall inside `[now - window, now]`.
    /// Extracted as a static so the decay math is testable without a live
    /// monitor or real filesystem sources.
    static func rollingWindowCount(events: [FileFeedEvent], now: Date = Date(), window: TimeInterval = 60) -> Int {
        let cutoff = now.addingTimeInterval(-window)
        return events.filter { $0.date > cutoff }.count
    }

    // MARK: Snapshot diff (confined to stateQueue)

    /// Marks the path dirty and schedules ONE drain. The event handler itself
    /// does no filesystem work.
    private func handleDirectoryChange(path: String) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            // A change arriving before the baseline landed would otherwise be
            // reported as thousands of spurious "created" events.
            guard self.baselineReady else { return }
            self.dirtyPaths.insert(path)
            guard !self.drainScheduled else { return }
            self.drainScheduled = true
            self.stateQueue.asyncAfter(deadline: .now() + Self.coalesceInterval) { [weak self] in
                self?.drain()
            }
        }
    }

    /// Re-scans every dirty directory once, then diffs.
    private func drain() {
        drainScheduled = false
        guard !dirtyPaths.isEmpty else { return }
        let paths = dirtyPaths
        dirtyPaths.removeAll()
        var batch: [FileFeedEvent] = []
        for path in paths {
            let old = snapshots[path] ?? [:]
            let current = snapshot(of: path)
            snapshots[path] = current
            for (name, meta) in current {
                let fullPath = (path as NSString).appendingPathComponent(name)
                if old[name] == nil {
                    batch.append(FileFeedEvent(date: Date(), path: fullPath, isCreated: true, attributedApp: Self.attributeApp(path: fullPath)))
                } else if let prev = old[name], prev.mtime != meta.mtime || prev.size != meta.size {
                    batch.append(FileFeedEvent(date: Date(), path: fullPath, isCreated: false, attributedApp: Self.attributeApp(path: fullPath)))
                }
                if batch.count >= 20 { break }
            }
            if batch.count >= 20 { break }
        }
        guard !batch.isEmpty else { return }
        DispatchQueue.main.async { [weak self, batch] in
            guard let self else { return }
            events.insert(contentsOf: batch, at: 0)
            if events.count > 500 {
                events = Array(events.prefix(500))
            }
            recomputeEventsPerMinute()
        }
    }

    private func snapshot(of dirPath: String) -> [String: FileMeta] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dirPath) else { return [:] }
        var result: [String: FileMeta] = [:]
        result.reserveCapacity(min(names.count, Self.maxSnapshotEntries))
        for (index, name) in names.enumerated() {
            if index >= Self.maxSnapshotEntries { break }
            let full = (dirPath as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: full) else { continue }
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            result[name] = FileMeta(mtime: mtime, size: size)
        }
        return result
    }

    /// Heuristic attribution: bundle-ish component after a known container dir.
    static func attributeApp(path: String) -> String? {
        let components = path.split(separator: "/")
        for marker in ["Caches", "HTTPStorages", "Application Support", "Logs"] {
            if let i = components.lastIndex(of: Substring(marker)), i + 1 < components.count {
                return String(components[i + 1])
            }
        }
        return nil
    }
}
