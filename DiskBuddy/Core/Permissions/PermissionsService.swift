import Foundation
import AppKit
@preconcurrency import UserNotifications

// MARK: - Real permission checks: Full Disk Access probe + notification status
//
// FDA has no API — the only honest signal is attempting to read known-protected
// locations. Granted if ANY probe succeeds; denied only if all probes fail
// with EPERM/EACCES (ENOENT is inconclusive and skipped). Re-checked every
// time the app becomes active (retained observer, removed in deinit).
// Main-confined in practice (all entry points run on main), hence Sendable.
final class PermissionsService: ObservableObject, @unchecked Sendable {
    @Published private(set) var fdaGranted = false
    @Published private(set) var fdaChecked = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var activeObserver: NSObjectProtocol?

    init() {
        checkAll()
        activeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in self?.checkAll() })
    }

    deinit {
        if let observer = activeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func checkAll() {
        fdaGranted = probeFullDiskAccess()
        fdaChecked = true
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let status = settings.authorizationStatus
            DispatchQueue.main.async { self.notificationStatus = status }
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            self?.checkAll()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func probeFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        // Only genuinely TCC-protected locations. Verified on hardware: these
        // all return NSFileReadNoPermissionError without Full Disk Access.
        // (Do not add unprotected paths here — a readable path makes the
        // probe report "granted" when it isn't.)
        let candidates = [
            "\(home)/Library/Mail",
            "\(home)/Library/Safari",
            "\(home)/Library/Messages",
            "/Library/Application Support/com.apple.TCC",
        ]
        var sawDenial = false
        for path in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue } // ENOENT: inconclusive
            do {
                if isDir.boolValue {
                    _ = try fm.contentsOfDirectory(atPath: path)
                } else {
                    _ = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
                }
                return true // readable → FDA granted
            } catch let error as NSError {
                if isPermissionDenied(error) { sawDenial = true }
                // anything else = inconclusive, try the next candidate
            }
        }
        // Every existing candidate was explicitly denied (or the probe was
        // inconclusive) → not granted. Either way we must not claim access.
        _ = sawDenial
        return false
    }

    /// NSError permission detection.
    ///
    /// The old code compared `error.code` against `EPERM` (1) and `EACCES`
    /// (13). But `FileManager.contentsOfDirectory` throws an **NSCocoaErrorDomain**
    /// error with code `NSFileReadNoPermissionError` = 257 — a value that
    /// matched neither, so a genuine denial was silently classified
    /// "inconclusive" and the probe only ever returned `false` by exhausting
    /// its candidate list.
    private func isPermissionDenied(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain {
            return error.code == EPERM || error.code == EACCES
        }
        if error.domain == NSCocoaErrorDomain {
            return error.code == NSFileReadNoPermissionError
                || error.code == NSFileWriteNoPermissionError
        }
        // Fall back to the underlying POSIX code when present.
        let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
        if let underlying { return underlying == EPERM || underlying == EACCES }
        return false
    }
}
