import Testing
import Foundation
@testable import DiskDoom

struct HardwareMonitorTests {
    @Test func cpuFirstSampleIsOnlyABaseline() {
        var sampler = SystemMonitor.CPUTickSampler()
        let cores = [SystemMonitor.CPUTicks(user: 10_000, idle: 20_000)]
        #expect(sampler.sample(cores) == nil)
        #expect(sampler.sample(cores) == nil)
        #expect(sampler.sample([.init(user: 10_025, idle: 20_075)]) == 25)
    }

    @Test func cpuHandlesSignedKernelCountersAndIndividualCoreWraps() {
        var sampler = SystemMonitor.CPUTickSampler()
        let high = UInt32(bitPattern: Int32.min)
        #expect(sampler.sample([
            .init(user: UInt32.max - 9, idle: high),
            .init(user: high, idle: high)
        ]) == nil)
        // Core 0 wraps by 20 ticks; core 1 advances by 30. Both idle
        // counters advance by 25. Cumulative sums exceed UInt32.max.
        #expect(sampler.sample([
            .init(user: 10, idle: high + 25),
            .init(user: high + 30, idle: high + 25)
        ]) == 50)
    }

    @Test func cpuAggregatesLargeDeltasIn64Bits() {
        var sampler = SystemMonitor.CPUTickSampler()
        #expect(sampler.sample(Array(repeating: .init(), count: 8)) == nil)
        #expect(sampler.sample(Array(repeating: .init(user: 3_000_000_000, idle: 3_000_000_000), count: 8)) == 50)
    }

    @Test func cpuCoreCountChangeReestablishesBaseline() {
        var sampler = SystemMonitor.CPUTickSampler()
        #expect(sampler.sample([.init(user: 100)]) == nil)
        #expect(sampler.sample([.init(user: 200), .init(user: 200)]) == nil)
        #expect(sampler.sample([.init(user: 210, idle: 10), .init(user: 210, idle: 10)]) == 50)
    }

    @Test func processUsesActualElapsedTimeAndAllowsMultipleCores() {
        var sampler = SystemMonitor.ProcessCPUSampler()
        #expect(sampler.sample(pid: 1, ticks: 20_000_000_000, time: 10, launchDate: nil) == nil)
        // A delayed refresh takes 8s, during which the process uses 16 CPU seconds.
        #expect(sampler.sample(pid: 1, ticks: 36_000_000_000, time: 18, launchDate: nil) == 200)
    }

    @Test func processZeroIsAValidBaselineButFailureIsNot() {
        var sampler = SystemMonitor.ProcessCPUSampler()
        #expect(sampler.sample(pid: 1, ticks: 0, time: 10, launchDate: nil) == nil)
        #expect(sampler.sample(pid: 1, ticks: 1_000_000_000, time: 11, launchDate: nil) == 100)
        #expect(sampler.sample(pid: 1, ticks: nil, time: 12, launchDate: nil) == nil)
        #expect(sampler.sample(pid: 1, ticks: 90_000_000_000, time: 13, launchDate: nil) == nil)
        #expect(sampler.sample(pid: 1, ticks: 91_000_000_000, time: 15, launchDate: nil) == 50)
        #expect(sampler.sample(pid: 1, ticks: 91_000_000_000, time: 16, launchDate: nil) == 0)
    }

    @Test func processCounterResetAndPIDReuseDoNotSpike() {
        var sampler = SystemMonitor.ProcessCPUSampler()
        let firstLaunch = Date(timeIntervalSince1970: 1)
        let nextLaunch = Date(timeIntervalSince1970: 2)
        #expect(sampler.sample(pid: 1, ticks: 100, time: 10, launchDate: firstLaunch) == nil)
        #expect(sampler.sample(pid: 1, ticks: 50, time: 11, launchDate: firstLaunch) == nil)
        #expect(sampler.sample(pid: 1, ticks: 100_000_000_000, time: 12, launchDate: nextLaunch) == nil)
        sampler.retain(pids: [])
        #expect(sampler.sample(pid: 1, ticks: 200_000_000_000, time: 13, launchDate: nextLaunch) == nil)
    }

    @Test func processNonpositiveIntervalDoesNotDivideByZero() {
        var sampler = SystemMonitor.ProcessCPUSampler()
        #expect(sampler.sample(pid: 1, ticks: 0, time: 10, launchDate: nil) == nil)
        #expect(sampler.sample(pid: 1, ticks: 1, time: 10, launchDate: nil) == nil)
        #expect(sampler.sample(pid: 1, ticks: 2, time: 9, launchDate: nil) == nil)
    }

    @Test func memoryStartsUnavailableRatherThanFabricated() {
        let monitor = SystemMonitor()
        #expect(!monitor.isMemoryAvailable)
        #expect(monitor.memoryTotalGB == Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
    }
}
