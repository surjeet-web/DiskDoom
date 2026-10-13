import Foundation
import AppKit
@preconcurrency import Darwin

// MARK: - Real system stats: CPU load, VM memory, uptime, running apps
//
// No special entitlements needed: host_processor_info + host_statistics give
// system-wide CPU/memory; NSWorkspace gives the app list; proc_pidinfo gives
// per-process resident memory for same-user processes (SIP-protected ones
// are marked unavailable — never fabricated).

struct LiveProcess: Identifiable {
    let pid: Int32
    var id: Int32 { pid }
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let launchDate: Date?
    let residentBytes: Int64
    var isResidentMemoryAvailable: Bool = true
    var cpuMeasurement: Measurement<Double> = .notMeasured
    /// An ordering key, never a displayed measurement. Unknown values sort last.
    var cpuSortValue: Double { cpuMeasurement.availableValue ?? -.infinity }
}

final class SystemMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var cpuMeasurement: Measurement<Double> = .notMeasured
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var memoryTotalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    @Published private(set) var isMemoryAvailable = false
    @Published private(set) var uptimeText = ""
    @Published private(set) var processes: [LiveProcess] = []

    private var timer: Timer?
    private var cpuSampler = CPUTickSampler()
    private var processSampler = ProcessCPUSampler()
    private var tick = 0
    /// Icons are expensive to load (disk I/O) — cache one per bundle path.
    /// Main-thread confined (all sampling happens on the main actor).
    private var iconCache: [String: NSImage] = [:]

    deinit { timer?.invalidate() }

    struct CPUTicks {
        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0
    }

    /// Keep each kernel counter's 32-bit wrapping semantics, then aggregate
    /// deltas in 64 bits. Summing cumulative counters first loses core wraps.
    struct CPUTickSampler {
        private var previous: [CPUTicks]?

        mutating func sample(_ cores: [CPUTicks]) -> Double? {
            defer { previous = cores }
            guard let previous, !cores.isEmpty, previous.count == cores.count else { return nil }
            var busy: UInt64 = 0
            var idle: UInt64 = 0
            for (current, old) in zip(cores, previous) {
                busy += UInt64(current.user &- old.user)
                busy += UInt64(current.system &- old.system)
                busy += UInt64(current.nice &- old.nice)
                idle += UInt64(current.idle &- old.idle)
            }
            let total = busy + idle
            guard total > 0 else { return nil }
            return Double(busy) / Double(total) * 100
        }
    }

    struct ProcessCPUSampler {
        private struct Baseline {
            let ticks: UInt64
            let time: TimeInterval
            let launchDate: Date?
        }
        private var previous: [Int32: Baseline] = [:]

        mutating func sample(pid: Int32, ticks: UInt64?, time: TimeInterval, launchDate: Date?) -> Double? {
            guard let ticks else {
                previous.removeValue(forKey: pid)
                return nil
            }
            let old = previous.updateValue(Baseline(ticks: ticks, time: time, launchDate: launchDate), forKey: pid)
            guard let old, old.launchDate == launchDate, ticks >= old.ticks,
                  time.isFinite, old.time.isFinite, time > old.time else { return nil }
            // 100% is one fully occupied core; a process can use multiple cores.
            return Double(ticks - old.ticks) / 1_000_000_000 / (time - old.time) * 100
        }

        mutating func retain(pids: Set<Int32>) {
            previous = previous.filter { pids.contains($0.key) }
        }
    }

    func start() {
        guard timer == nil else { return }
        cpuSampler = CPUTickSampler()
        cpuMeasurement = .notMeasured
        processSampler = ProcessCPUSampler()
        tick = 0
        Task { @MainActor [weak self] in
            guard let self, self.timer != nil else { return }
            self.sample()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.timer != nil else { return }
                self.sample()
            }
        }
        timer?.tolerance = 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func sample() {
        tick += 1
        sampleCPU()
        sampleMemory()
        sampleUptime()
        // Process sampling (icon loads + proc_pidinfo per app) every 3s,
        // not every tick — 1s made the whole UI stutter on icon I/O.
        if tick % 3 == 1 {
            sampleProcesses()
        }
    }

    // MARK: CPU (host_processor_info, all cores averaged)

    private func sampleCPU() {
        // mach_host.h: (host, flavor, out_processor_count, out_processor_info,
        // out_processor_infoCnt). All three outs are required — a nil count
        // pointer faults inside the kernel call (that was the Monitor crash).
        // The info buffer is kernel-allocated and must be vm_deallocated.
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else {
            cpuSampler = CPUTickSampler()
            cpuMeasurement = .unavailable(reason: "host_processor_info failed")
            return
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        guard cpuCount > 0, cpuCount <= 1024,
              Int(infoCount) >= Int(cpuCount) * Int(CPU_STATE_MAX) else {
            cpuSampler = CPUTickSampler()
            cpuMeasurement = .unavailable(reason: "Invalid CPU counter buffer")
            return
        }
        let nCPU = Int(cpuCount)
        var cores: [CPUTicks] = []
        cores.reserveCapacity(nCPU)
        for i in 0..<nCPU {
            let base = i * Int(CPU_STATE_MAX)
            cores.append(CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
        if let percent = cpuSampler.sample(cores) {
            cpuMeasurement = .available(value: percent, measuredAt: Date(), source: "host_processor_info tick delta")
        } else {
            cpuMeasurement = .notMeasured
        }
    }

    // MARK: Memory (host_statistics64)

    private func sampleMemory() {
        var size: mach_msg_type_number_t = UInt32(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            isMemoryAvailable = false
            return
        }
        let pageSize = Double(getpagesize())
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let free = Double(vmStat.free_count) * pageSize
        memoryTotalGB = total / 1_073_741_824
        isMemoryAvailable = true
        memoryUsedGB = max(0, total - free) / 1_073_741_824
    }

    // MARK: Uptime (kern.boottime)

    private func sampleUptime() {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return }
        let up = Int(Date().timeIntervalSince1970) - Int(boot.tv_sec)
        let d = up / 86_400, h = (up % 86_400) / 3600, m = (up % 3600) / 60
        uptimeText = d > 0 ? "\(d)d \(h)h \(m)m" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    // MARK: Processes (NSWorkspace list + proc_pidinfo deltas)

    private func sampleProcesses() {
        let running = NSWorkspace.shared.runningApplications
        var updated: [LiveProcess] = []
        var seenPIDs = Set<Int32>()
        var seenIconPaths = Set<String>()
        for app in running {
            let pid = app.processIdentifier
            seenPIDs.insert(pid)
            let info = taskInfo(pid: pid)
            let cpu = processSampler.sample(
                pid: pid, ticks: info.map { $0.pti_total_user &+ $0.pti_total_system },
                time: ProcessInfo.processInfo.systemUptime, launchDate: app.launchDate)
            // Cached icon: load once per bundle path, never per sample.
            // icon(forFile:) never traps (unlike NSRunningApplication.icon
            // IUU); fall back to a guaranteed-present path for icon-less PIDs.
            let iconPath = app.bundleURL?.path ?? app.executableURL?.path ?? "/bin/ls"
            seenIconPaths.insert(iconPath)
            let icon: NSImage
            if let cached = iconCache[iconPath] {
                icon = cached
            } else {
                let loaded = NSWorkspace.shared.icon(forFile: iconPath)
                loaded.size = NSSize(width: 16, height: 16)
                iconCache[iconPath] = loaded
                icon = loaded
            }
            updated.append(LiveProcess(
                pid: pid,
                name: app.localizedName ?? "Unknown",
                bundleIdentifier: app.bundleIdentifier,
                icon: icon,
                launchDate: app.launchDate,
                residentBytes: info.map { Int64(clamping: $0.pti_resident_size) } ?? 0,
                isResidentMemoryAvailable: info != nil,
                cpuMeasurement: Self.processCPUMeasurement(percent: cpu, readSucceeded: info != nil, measuredAt: Date())))
        }
        processSampler.retain(pids: seenPIDs)
        iconCache = iconCache.filter { seenIconPaths.contains($0.key) }
        processes = updated.sorted { $0.cpuSortValue > $1.cpuSortValue }
    }

    private func taskInfo(pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == size else { return nil }
        return info
    }

    static func processCPUMeasurement(percent: Double?, readSucceeded: Bool, measuredAt: Date) -> Measurement<Double> {
        guard readSucceeded else { return .unavailable(reason: "proc_pidinfo failed or access denied") }
        guard let percent else { return .notMeasured }
        guard percent.isFinite, percent >= 0 else { return .error(reason: "Invalid process CPU delta") }
        return .available(value: percent, measuredAt: measuredAt, source: "proc_pidinfo CPU delta")
    }
}

/// A history contains evidence, never startup padding or failed reads.
struct MonitorSampleHistory {
    struct Sample: Equatable {
        let value: Double
        let measuredAt: Date
    }
    private(set) var samples: [Sample] = []
    mutating func append(_ measurement: Measurement<Double>, limit: Int = 60) {
        guard case .available(let value, let date, _) = measurement,
              value.isFinite, limit > 0 else { return }
        guard samples.last?.measuredAt != date else { return }
        samples.append(Sample(value: value, measuredAt: date))
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }
}
