import Foundation

// MARK: - Single shared byte formatter (all user-facing sizes go through here)

enum ByteFormatting {
    static func format(_ bytes: Int64) -> String {
        // Fresh instance per call: ByteCountFormatter is not Sendable, so no
        // shared static instance (even lock-guarded ones still trip the
        // Swift 6 Sendable checker at the declaration site).
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
