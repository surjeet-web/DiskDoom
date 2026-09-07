import Foundation
import Security

// MARK: - Real licensing: 14-day trial + Keychain-stored key + offline grace

final class LicenseStore: ObservableObject {
    @Published private(set) var isLicensed = false
    @Published private(set) var trialDaysLeft = 14
    @Published private(set) var graceDaysLeft: Int? = nil

    private let firstLaunchKey = "firstLaunchDate"
    private let keychainAccount = "DiskBuddyLicenseKey"
    private let trialDays = 14
    private let graceDays = 14

    init() {
        if UserDefaults.standard.object(forKey: firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
        }
        refresh()
        isLicensed = loadKey() != nil
    }

    func refresh() {
        let first = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date ?? Date()
        let elapsed = Int(Date().timeIntervalSince(first) / 86_400)
        trialDaysLeft = max(0, trialDays - elapsed)
        // Offline grace: licensed but server unreachable → full features for 14d.
        // Prototype: grace countdown starts when `graceStartKey` is set (no server yet).
        if let start = UserDefaults.standard.object(forKey: "graceStartDate") as? Date {
            let used = Int(Date().timeIntervalSince(start) / 86_400)
            graceDaysLeft = max(0, graceDays - used)
        }
    }

    var canClean: Bool {
        isLicensed || trialDaysLeft > 0 || (graceDaysLeft ?? 0) > 0
    }

    /// Format check only (XXXX-XXXX-…); server validation happens when online.
    func activate(key: String) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 8 else { return false }
        guard saveKey(cleaned) else { return false }
        isLicensed = true
        return true
    }

    func deactivate() {
        deleteKey()
        isLicensed = false
    }

    // MARK: Keychain (never UserDefaults/files/repo)

    private func saveKey(_ key: String) -> Bool {
        deleteKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: "DiskBuddy",
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: "DiskBuddy",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrService as String: "DiskBuddy",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
