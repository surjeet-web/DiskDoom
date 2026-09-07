import Foundation
import UserNotifications
import AppKit

// MARK: - Real system notifications (scan done, cleanup done, monitor alerts)

final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let categoryScan = "SCAN_DONE"
    static let categoryCleanup = "CLEANUP_DONE"
    static let categoryMonitor = "MONITOR_ALERT"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func post(title: String, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(category)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func postScanComplete(files: Int, bytes: Int64, seconds: Double) {
        post(title: "Scan complete",
             body: "\(files.formatted()) files · \(ByteFormatting.format(bytes)) · \(String(format: "%.1f", seconds))s",
             category: Self.categoryScan)
    }

    func postCleanupComplete(items: Int, freed: Int64) {
        post(title: "Cleanup complete",
             body: "Moved \(items) items to Trash · \(ByteFormatting.format(freed)) freed",
             category: Self.categoryCleanup)
    }

    func postMonitorAlert(appName: String, bytes: Int64) {
        post(title: "DiskDoom",
             body: "\(appName) left \(ByteFormatting.format(bytes)) of new caches.",
             category: Self.categoryMonitor)
    }

    // Show banners even while the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Tapping a notification focuses the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}
