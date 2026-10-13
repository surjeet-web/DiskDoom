import Foundation
import os
@preconcurrency import Darwin

// MARK: - Performance logging for key operations.
//
// Wraps heavy work (scan, duplicate hashing, inventory) and logs slow
// operations to os_log so regressions are visible in Console.app and
// Instruments before users complain. Zero overhead when fast.

enum PerformanceMonitor {
    private static let logger = Logger(subsystem: "com.diskdoom.DiskDoom", category: "performance")

    /// Time a synchronous block; log a warning when it exceeds `threshold`.
    static func measure<T>(_ name: String, threshold: TimeInterval = 1.0, block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        log(name: name, elapsed: CFAbsoluteTimeGetCurrent() - start, threshold: threshold)
        return result
    }

    /// Async variant.
    static func measure<T>(_ name: String, threshold: TimeInterval = 1.0, block: @Sendable () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        log(name: name, elapsed: CFAbsoluteTimeGetCurrent() - start, threshold: threshold)
        return result
    }

    private static func log(name: String, elapsed: TimeInterval, threshold: TimeInterval) {
        if elapsed > threshold {
            logger.warning("Slow: \(name, privacy: .public) took \(String(format: "%.2f", elapsed), privacy: .public)s (threshold \(String(format: "%.1f", threshold), privacy: .public)s)")
        } else {
            logger.debug("\(name, privacy: .public): \(String(format: "%.3f", elapsed), privacy: .public)s")
        }
    }

    /// Resident memory of this process.
    static func memoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }

    /// Log a warning when resident memory crosses `warningMB`.
    static func checkMemory(label: String, warningMB: Int = 500) {
        let mb = memoryUsage() / 1_048_576
        if mb > warningMB {
            logger.warning("Memory: \(label, privacy: .public) using \(mb)MB")
        }
    }
}
