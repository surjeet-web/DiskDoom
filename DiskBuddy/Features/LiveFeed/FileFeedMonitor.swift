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
// - `snapshots` is touched only on `stateQueue` (serial).
// - `events`, `isMonitoring`, `eventsPerMinute` are touched only on main.
// - `sources` is touched on start/stop (main, from UI) and deinit
//   (DispatchSource.cancel is thread-safe).
final class FileFeedMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var events: [FileFeedEvent] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var eventsPerMinute = 0

    private var sources: [DispatchSourceFileSystemObject] = []
    private let workQueue = DispatchQueue(label: "com.diskbuddy.filefeed", qos: .utility)
    /// Snapshot state is confined to `stateQueue`; never touched elsewhere.
    private let stateQueue = DispatchQueue(label: "com.diskbuddy.filefeed.state", qos: .utility)
    private var snapshots: [String: [String: FileMeta]] = [:]

    private struct FileMeta {
        let mtime: TimeInterval
        let size: Int64
    }

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
        // Mock seed so the prototype UI is demonstrable before monitoring starts.
        let now = Date()
        events = [
            FileFeedEvent(date: now, path: "\(watchPaths[0])/com.google.Chrome/Cache/data_3", isCreated: true, attributedApp: "com.google.Chrome"),
            FileFeedEvent(date: now.addingTimeInterval(-40), path: "\(watchPaths[3])/installer-2.dmg", isCreated: true, attributedApp: nil),
            FileFeedEvent(date: now.addingTimeInterval(-95), path: "\(watchPaths[2])/GoogleSoftwareUpdate/agent.log", isCreated: false, attributedApp: "GoogleSoftwareUpdate"),
        ]
    }

    func start() {
        guard sources.isEmpty else { return }
        // Baseline first so enabling monitoring doesn't flood with history.
        stateQueue.sync {
            for path in watchPaths {
                snapshots[path] = snapshot(of: path)
            }
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
    }

    func stop() {
        for source in sources { source.cancel() }
        sources.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.isMonitoring = false
        }
    }

    deinit {
        for source in sources { source.cancel() }
    }

    // MARK: Snapshot diff (confined to stateQueue)

    private func handleDirectoryChange(path: String) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            let old = snapshots[path] ?? [:]
            let current = snapshot(of: path)
            snapshots[path] = current
            var batch: [FileFeedEvent] = []
            for (name, meta) in current {
                let fullPath = (path as NSString).appendingPathComponent(name)
                if old[name] == nil {
                    batch.append(FileFeedEvent(date: Date(), path: fullPath, isCreated: true, attributedApp: Self.attributeApp(path: fullPath)))
                } else if let prev = old[name], prev.mtime != meta.mtime || prev.size != meta.size {
                    batch.append(FileFeedEvent(date: Date(), path: fullPath, isCreated: false, attributedApp: Self.attributeApp(path: fullPath)))
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
                let cutoff = Date().addingTimeInterval(-60)
                eventsPerMinute = events.filter { $0.date > cutoff }.count
            }
        }
    }

    private func snapshot(of dirPath: String) -> [String: FileMeta] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dirPath) else { return [:] }
        var result: [String: FileMeta] = [:]
        result.reserveCapacity(names.count)
        for name in names {
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
