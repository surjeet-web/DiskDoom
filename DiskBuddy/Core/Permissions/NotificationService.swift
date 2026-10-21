import Foundation
import UserNotifications
import AppKit

// MARK: - Real system notifications (scan done, cleanup done, monitor alerts,
// menu-bar space alerts + weekly digest)

// No mutable stored state. Notification-center APIs support concurrent calls;
// AppKit activation in the delegate is explicitly dispatched to the main queue.
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let categoryScan = "SCAN_DONE"
    static let categoryCleanup = "CLEANUP_DONE"
    static let categoryMonitor = "MONITOR_ALERT"
    static let categorySpaceAlert = "SPACE_ALERT"
    static let categoryGamification = "GAMIFICATION"
    static let weeklyDigestID = "diskdoom-weekly-digest"

    private override init() {
        super.init()
        // Space alerts carry [Open DiskDoom] [Later] actions.
        let openAction = UNNotificationAction(
            identifier: "OPEN_APP", title: "Open DiskDoom", options: .foreground)
        let laterAction = UNNotificationAction(
            identifier: "DISMISS", title: "Later", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categorySpaceAlert,
                actions: [openAction, laterAction],
                intentIdentifiers: [])
        ])
        UNUserNotificationCenter.current().delegate = self
    }

    /// Single shared instance. `UNUserNotificationCenter.delegate` is a *weak*
    /// reference, so creating a second `NotificationService` re-pointed the
    /// delegate at a throwaway object that was immediately deallocated —
    /// silently killing every foreground notification. Always use `shared`.
    static let shared = NotificationService()

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
        // Authorization is never requested on the scan/alert paths, so with
        // the default settings every one of these calls silently failed with
        // "Notifications are not allowed". Check first and surface it once
        // instead of pretending it worked.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                UNUserNotificationCenter.current().add(request) { error in
                    if let error {
                        NSLog("DiskDoom: notification not posted — \(error.localizedDescription)")
                    }
                }
            case .notDetermined:
                NSLog("DiskDoom: notification '\(title)' skipped — permission never requested")
            case .denied:
                NSLog("DiskDoom: notification '\(title)' skipped — permission denied")
            @unknown default:
                break
            }
        }
    }

    func postScanComplete(files: Int, bytes: Int64, seconds: Double) {
        post(title: "Scan complete",
             body: "\(files.formatted()) files · \(ByteFormatting.format(bytes)) · \(String(format: "%.1f", seconds))s",
             category: Self.categoryScan)
    }

    func postCleanupComplete(items: Int, freed: Int64) {
        post(title: "Cleanup complete",
              body: "Moved \(items) items (\(ByteFormatting.format(freed))) to Trash. Empty Trash to reclaim space.",
             category: Self.categoryCleanup)
    }

    func postGamification(title: String, body: String) {
        post(title: title, body: body, category: Self.categoryGamification)
    }

    func postDuplicateAlert(newSets: Int, folderCount: Int, bytes: Int64) {
        post(title: "New duplicates found",
             body: "\(newSets) new set\(newSets == 1 ? "" : "s") across \(folderCount) watched folder\(folderCount == 1 ? "" : "s") · \(ByteFormatting.format(bytes)) potential.",
             category: Self.categoryMonitor)
    }

    func postMonitorAlert(appName: String, bytes: Int64) {
        post(title: "DiskDoom",
             body: "\(appName) left \(ByteFormatting.format(bytes)) of new caches.",
             category: Self.categoryMonitor)
    }

    // MARK: Menu bar feature: disk space alerts + weekly digest

    /// Alert when free space crosses a threshold (menu bar monitor drives this).
    func sendDiskSpaceAlert(title: String, freeSpace: Int64, freePercent: Double) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Only \(ByteFormatting.format(freeSpace)) free (\(String(format: "%.0f", freePercent))%). Open DiskDoom to clean up."
        content.sound = .default
        content.categoryIdentifier = Self.categorySpaceAlert
        let request = UNNotificationRequest(
            identifier: "\(Self.categorySpaceAlert)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    /// Weekly digest, Monday 9 AM local time, repeating.
    func scheduleWeeklyDigest() {
        let content = UNMutableNotificationContent()
        content.title = "Weekly Disk Report"
        content.body = "Open DiskDoom to see your weekly storage summary and recommendations."
        content.sound = .default
        var components = DateComponents()
        components.weekday = 2 // Monday
        components.hour = 9
        components.minute = 0
        let request = UNNotificationRequest(
            identifier: Self.weeklyDigestID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestID])
        UNUserNotificationCenter.current().add(request)
    }

    func cancelWeeklyDigest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestID])
    }

    // Show banners even while the app is frontmost.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Tapping a notification (or its Open DiskDoom action) focuses the app.
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
