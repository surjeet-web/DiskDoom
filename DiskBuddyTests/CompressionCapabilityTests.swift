import Foundation
import XCTest
@testable import DiskDoom

final class CompressionCapabilityTests: XCTestCase {
    func testCapabilityMatchesDocumentedVolumeResourceValue() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try home.resourceValues(forKeys: [.volumeSupportsCompressionKey])
        XCTAssertEqual(SmartCompressionEngine.volumeSupportsCompression(at: home.path),
                       values.volumeSupportsCompression == true)
    }

    func testUnknownVolumeCapabilityIsRefused() {
        let path = "/nonexistent-diskbuddy-\(UUID().uuidString)/file.txt"
        XCTAssertFalse(SmartCompressionEngine.volumeSupportsCompression(at: path))
    }
}
