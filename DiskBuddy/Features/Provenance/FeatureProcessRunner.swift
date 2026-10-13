import Foundation
import Darwin

/// For small feature commands only. Run off-main; no pipe read or process
/// wait can keep its caller blocked indefinitely.
enum FeatureProcessRunner {
    static func run(executable: String, arguments: [String], timeout: TimeInterval,
                    captureOutput: Bool = true, outputLimit: Int = 1_048_576,
                    cancellation: ScanCancellation = .never) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }

        // A file avoids the pipe-buffer deadlock and lets us read a bounded
        // amount even if a command emits unexpected output.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskbuddy-command-\(UUID().uuidString)", isDirectory: true)
        var output: FileHandle?
        defer {
            try? output?.close()
            if captureOutput { try? FileManager.default.removeItem(at: directory) }
        }
        if captureOutput {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let file = directory.appendingPathComponent("stdout")
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            output = try FileHandle(forUpdating: file)
        }
        process.standardOutput = output ?? FileHandle.nullDevice
        if cancellation.isCancelled { throw CancellationError() }
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while completed.wait(timeout: .now() + 0.1) == .timedOut {
            if cancellation.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                process.terminate()
                if completed.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = completed.wait(timeout: .now() + 1)
                }
                if cancellation.isCancelled { throw CancellationError() }
                throw NSError(domain: "DiskBuddy.FeatureProcess", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Command timed out: \(executable)"])
            }
        }
        if cancellation.isCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DiskBuddy.FeatureProcess", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Command failed: \(executable) (\(process.terminationStatus))"])
        }
        guard let output else { return Data() }
        try output.seek(toOffset: 0)
        let data = try output.read(upToCount: max(0, outputLimit) + 1) ?? Data()
        guard data.count <= outputLimit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
