import Foundation

// MARK: - Launch orchestration: explicit phases, correct completion, bounded work
//
// Review-driven design (NOT a serial UI-blocking chain):
// - The window appears immediately; .task runs post-appear. Nothing here
//   blocks first paint — jobs hydrate caches progressively.
// - Foreground jobs are @MainActor closures run sequentially (all fast).
// - Background jobs are @Sendable closures touching only @unchecked Sendable
//   engines, run in detached tasks bounded to 2 concurrent workers.
// - Heavy lifting lives INSIDE engines (which self-background); the
//   coordinator only dispatches, so there is no launch-time CPU war.

enum LaunchPhase: String {
    case starting, hydrating, ready, warming, complete
}

enum LaunchJobPriority: Int, CaseIterable {
    case critical = 0 // license, permissions, persisted snapshots
    case high = 1 // fast derived state for first paint
    case background = 2 // everything else, 2 at a time
}

struct LaunchForegroundJob {
    let id = UUID()
    let name: String
    let priority: LaunchJobPriority
    let action: @MainActor () async -> Void
}

struct LaunchBackgroundJob: Sendable {
    let id = UUID()
    let name: String
    let action: @Sendable () async -> Void
}

enum LaunchJobStatus: String, Sendable {
    case completed, skipped
}

struct LaunchJobResult: Identifiable, Sendable {
    let id: UUID // == job id
    let name: String
    let priority: LaunchJobPriority
    let status: LaunchJobStatus
    let duration: TimeInterval
}

/// Bounded worker pool (review: no unbounded task-group fan-out).
private actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ permits: Int) {
        self.permits = permits
    }

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            permits += 1
        }
    }
}

@MainActor
final class LaunchCoordinator: ObservableObject {
    @Published private(set) var phase: LaunchPhase = .starting
    @Published private(set) var results: [LaunchJobResult] = []
    @Published private(set) var currentJobName = ""
    @Published private(set) var staleCache = false

    private var foregroundJobs: [LaunchForegroundJob] = []
    private var backgroundJobs: [LaunchBackgroundJob] = []

    func registerForeground(name: String, priority: LaunchJobPriority = .critical, action: @escaping @MainActor () async -> Void) {
        foregroundJobs.append(LaunchForegroundJob(name: name, priority: priority, action: action))
        foregroundJobs.sort { $0.priority.rawValue < $1.priority.rawValue }
    }

    func registerBackground(name: String, action: @escaping @Sendable () async -> Void) {
        backgroundJobs.append(LaunchBackgroundJob(name: name, action: action))
    }

    /// Correct completion: required foreground IDs ⊆ completed IDs.
    var allCriticalDone: Bool {
        let required = Set(foregroundJobs.filter { $0.priority == .critical }.map(\.id))
        let completed = Set(results.filter { $0.status == .completed }.map(\.id))
        return required.isSubset(of: completed)
    }

    func runAll() async {
        phase = .hydrating
        for job in foregroundJobs {
            await executeForeground(job)
        }
        phase = .ready
        // Bounded background execution: max 2 concurrent workers.
        let semaphore = AsyncSemaphore(2)
        let jobs = backgroundJobs
        await withTaskGroup(of: LaunchJobResult.self) { group in
            for job in jobs {
                group.addTask {
                    await semaphore.wait()
                    let start = Date()
                    await job.action()
                    await semaphore.signal()
                    return LaunchJobResult(id: job.id, name: job.name, priority: .background, status: .completed, duration: Date().timeIntervalSince(start))
                }
            }
            for await result in group {
                record(result)
            }
        }
        phase = .complete
    }

    private func executeForeground(_ job: LaunchForegroundJob) async {
        currentJobName = job.name
        let start = Date()
        await job.action()
        record(LaunchJobResult(id: job.id, name: job.name, priority: job.priority, status: .completed, duration: Date().timeIntervalSince(start)))
    }

    private func record(_ result: LaunchJobResult) {
        results.append(result)
        completedCount += 1
    }

    @Published private(set) var completedCount = 0

    func markCacheStale() {
        staleCache = true
    }
}
