import Foundation
import AppKit
import UserNotifications

// MARK: - Real permission checks: Full Disk Access probe + notification status
//
// FDA has no API — the only honest signal is attempting to read known-protected
// locations. Granted if ANY probe succeeds; denied only if all probes fail
// with EPERM/EACCES (ENOENT is inconclusive and skipped). Re-checked every
// time the app becomes active (retained observer, removed in deinit).

final class PermissionsService: ObservableObject {
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
            DispatchQueue.main.async { self?.notificationStatus = settings.authorizationStatus }
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
        let candidates = [
            "\(home)/Library/Mail",
            "\(home)/Library/Safari",
            "\(home)/Library/Messages",
            "/Library/Application Support/com.apple.TCC",
        ]
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
                // EPERM/EACCES = blocked; anything else = inconclusive, try next.
                if error.code != EPERM && error.code != EACCES { continue }
            }
        }
        return false
    }
}
