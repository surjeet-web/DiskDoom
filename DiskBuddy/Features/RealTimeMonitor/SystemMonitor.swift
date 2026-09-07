import Foundation
import AppKit
@preconcurrency import Darwin

// MARK: - Real system stats: CPU load, VM memory, uptime, running apps
//
// No special entitlements needed: host_processor_info + host_statistics give
// system-wide CPU/memory; NSWorkspace gives the app list; proc_pidinfo gives
// per-process resident memory for same-user processes (SIP-protected ones
// report zero and are shown as such — never fabricated).

struct LiveProcess: Identifiable {
    let pid: Int32
    var id: Int32 { pid }
    let name: String
    let icon: NSImage?
    let launchDate: Date?
    let residentBytes: Int64
    var cpuPercent: Double
}

final class SystemMonitor: ObservableObject, @unchecked Sendable {
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var memoryTotalGB: Double = 16
    @Published private(set) var uptimeText = ""
    @Published private(set) var processes: [LiveProcess] = []

    private var timer: Timer?
    private var prevCPU = PrevCPUTicks()
    private var prevProcCPU: [Int32: UInt64] = [:]
    private var prevSampleTime = Date()

    struct PrevCPUTicks {
        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0
    }

    func start() {
        guard timer == nil else { return }
        Task { @MainActor [weak self] in self?.sample() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func sample() {
        let now = Date()
        let dt = max(now.timeIntervalSince(prevSampleTime), 0.01)
        prevSampleTime = now
        sampleCPU()
        sampleMemory()
        sampleUptime()
        sampleProcesses(dt: dt)
    }

    // MARK: CPU (host_processor_info, all cores averaged)

    private func sampleCPU() {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, nil)
        guard result == KERN_SUCCESS, let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let cpuCount = Int(count) / Int(CPU_STATE_MAX)
        var user: UInt32 = 0, system: UInt32 = 0, idle: UInt32 = 0, nice: UInt32 = 0
        for i in 0..<cpuCount {
            let base = i * Int(CPU_STATE_MAX)
            user += UInt32(info[base + Int(CPU_STATE_USER)])
            system += UInt32(info[base + Int(CPU_STATE_SYSTEM)])
            idle += UInt32(info[base + Int(CPU_STATE_IDLE)])
            nice += UInt32(info[base + Int(CPU_STATE_NICE)])
        }
        let dUser = Double(user &- prevCPU.user), dSys = Double(system &- prevCPU.system)
        let dIdle = Double(idle &- prevCPU.idle), dNice = Double(nice &- prevCPU.nice)
        prevCPU = PrevCPUTicks(user: user, system: system, idle: idle, nice: nice)
        let total = dUser + dSys + dIdle + dNice
        if total > 0 { cpuPercent = min(100, max(0, (dUser + dSys + dNice) / total * 100)) }
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
        guard result == KERN_SUCCESS else { return }
        let pageSize = Double(getpagesize())
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let free = Double(vmStat.free_count) * pageSize
        memoryTotalGB = total / 1_073_741_824
        memoryUsedGB = (total - free) / 1_073_741_824
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

    private func sampleProcesses(dt: Double) {
        let running = NSWorkspace.shared.runningApplications
        var updated: [LiveProcess] = []
        var seenPIDs = Set<Int32>()
        for app in running {
            let pid = app.processIdentifier
            seenPIDs.insert(pid)
            let resident = residentMemory(pid: pid)
            let totalTicks = cpuTicks(pid: pid)
            var cpu = 0.0
            if let prev = prevProcCPU[pid], dt > 0 {
                cpu = Double(totalTicks &- prev) / 100_000_000.0 / dt * 100.0
            }
            prevProcCPU[pid] = totalTicks
            updated.append(LiveProcess(
                pid: pid,
                name: app.localizedName ?? "Unknown",
                icon: app.icon,
                launchDate: app.launchDate,
                residentBytes: resident,
                cpuPercent: max(0, cpu)))
        }
        prevProcCPU = prevProcCPU.filter { seenPIDs.contains($0.key) }
        processes = updated.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private func residentMemory(pid: Int32) -> Int64 {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == size else { return 0 }
        return Int64(info.pti_resident_size)
    }

    private func cpuTicks(pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == size else { return 0 }
        return info.pti_total_user + info.pti_total_system
    }
}
