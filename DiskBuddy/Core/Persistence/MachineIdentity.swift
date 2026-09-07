import Foundation
import IOKit
import CryptoKit

// MARK: - Stable machine identity for license activation
//
// Server contract (validation.ts): hardware_hash 8–256 chars [A-Za-z0-9._:-],
// machine_id / platform_uuid 1–256 chars. The hash is a device identifier,
// not proof of hardware (per server README) — best-effort stability is what
// matters. Chain: IOPlatformUUID → hostname hash → persisted random UUID.

enum MachineIdentity {
    /// Stable per-machine platform UUID, or nil if unreadable.
    static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Short human-readable machine label (1–256 chars guaranteed).
    static func machineID() -> String {
        let name = Host.current().localizedName ?? "Mac"
        return String(name.prefix(64))
    }

    /// 64-hex-char hardware hash. Stable across launches for the same machine.
    static func hardwareHash() -> String {
        if let uuid = platformUUID() {
            return sha256Hex(uuid)
        }
        let host = Host.current().localizedName ?? "unknown-mac"
        if host != "unknown-mac" {
            return sha256Hex("diskbuddy:\(host)")
        }
        // Last resort: persisted random ID (stable per install, not per machine).
        let key = "machineFallbackID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = sha256Hex("diskbuddy:\(UUID().uuidString)")
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    static func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
