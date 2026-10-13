import Foundation
import Testing
@testable import DiskDoom

@Suite
struct FeatureTaskSafetyTests {
    @Test func subprocessTimeoutIsBounded() {
        let started = ProcessInfo.processInfo.systemUptime
        #expect(throws: (any Error).self) {
            try FeatureProcessRunner.run(executable: "/bin/sleep", arguments: ["30"], timeout: 0.1)
        }
        #expect(ProcessInfo.processInfo.systemUptime - started < 4)
    }

    @Test func subprocessOutputIsBounded() {
        #expect(throws: (any Error).self) {
            try FeatureProcessRunner.run(executable: "/usr/bin/printf",
                arguments: [String(repeating: "x", count: 100)], timeout: 2, outputLimit: 10)
        }
    }

    @Test @MainActor func cancelledScansCannotRepublishBusyState() async {
        let privacy = PrivacyScannerEngine()
        privacy.scan()
        privacy.cancel()
        let provenance = FileProvenanceEngine()
        provenance.analyze(path: "/nonexistent-diskbuddy-file")
        provenance.cancel()
        let compression = SmartCompressionEngine()
        compression.analyze(records: [])
        compression.cancel()
        let inventory = AppInventoryService()
        inventory.scan()
        inventory.cancel()
        for _ in 0..<20 { await Task.yield() }
        #expect(!privacy.isScanning)
        #expect(!provenance.isAnalyzing)
        #expect(!compression.isAnalyzing)
        #expect(!inventory.isScanning)
    }
}
