import Foundation
import Security

// MARK: - Licensing: 14-day trial + server-backed activation + Keychain secrets
//
// Online flow (server README §§8–10): activate(license_id+email) → device
// token in Keychain; validate on launch; deactivate frees the slot.
// Offline: 14-day grace with full features, then read-only (spec §85).
// Secrets live in Keychain (license ID, email, device token) — never
// UserDefaults, files, or the repo (server README note 8).

@MainActor
final class LicenseStore: ObservableObject {
    @Published private(set) var isLicensed = false
    @Published private(set) var trialDaysLeft = 14
    @Published private(set) var graceDaysLeft: Int? = nil
    @Published private(set) var lastServerMessage: String? = nil
    @Published private(set) var serverReachable = true
    @Published private(set) var updateAvailable: String? = nil
    @Published private(set) var isWorking = false
    @Published var serverOverride = ""

    private let firstLaunchKey = "firstLaunchDate"
    private let graceStartKey = "graceStartDate"
    private let serverURLKey = "licenseServerBaseURL"
    private let trialDays = 14
    private let graceDays = 14

    static let defaultServerURL = URL(string: "https://api.diskbuddy.com/v1")!

    init() {
        if UserDefaults.standard.object(forKey: firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
        }
        serverOverride = UserDefaults.standard.string(forKey: serverURLKey) ?? ""
        refresh()
        isLicensed = storedLicenseID() != nil
    }

    var serverBaseURL: URL {
        let trimmed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: trimmed) {
            UserDefaults.standard.set(trimmed, forKey: serverURLKey)
            return url
        }
        return Self.defaultServerURL
    }

    func refresh() {
        let first = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date ?? Date()
        trialDaysLeft = max(0, trialDays - Int(Date().timeIntervalSince(first) / 86_400))
        if let start = UserDefaults.standard.object(forKey: graceStartKey) as? Date {
            graceDaysLeft = max(0, graceDays - Int(Date().timeIntervalSince(start) / 86_400))
        }
    }

    var canClean: Bool {
        isLicensed || trialDaysLeft > 0 || (graceDaysLeft ?? 0) > 0
    }

    // MARK: Online activation (server §8)

    /// Returns true when licensed (or offline grace started). Message explains otherwise.
    func activateOnline(licenseID: String, email: String) async -> Bool {
        let id = licenseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausibleLicenseID(id) else {
            lastServerMessage = "That license key format looks wrong — check for typos."
            return false
        }
        guard Self.isPlausibleEmail(mail) else {
            lastServerMessage = "Enter the email address used at purchase."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        let server = LicenseServer(baseURL: serverBaseURL)
        let identity = Self.identity()
        do {
            let response = try await server.activate(
                licenseID: id, email: mail,
                hardwareHash: identity.hash, machineID: identity.machine,
                platformUUID: identity.platform, appVersion: identity.version)
            guard response.success else {
                lastServerMessage = response.message
                return false
            }
            if let token = response.deviceToken {
                saveSecret(token, account: tokenAccount(for: id))
            }
            saveSecret(id, account: "DiskBuddyLicenseID")
            saveSecret(mail, account: "DiskBuddyLicenseEmail")
            isLicensed = true
            serverReachable = true
            lastServerMessage = response.message
            return true
        } catch let error as LicenseServer.ServerError {
            return handleServerError(error, context: "activation")
        } catch {
            lastServerMessage = "Activation failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Launch validation (server §9)

    func validateOnLaunch() async {
        guard let id = storedLicenseID() else { return } // trial path, nothing to check
        let server = LicenseServer(baseURL: serverBaseURL)
        let identity = Self.identity()
        do {
            let response = try await server.validate(
                licenseID: id,
                hardwareHash: identity.hash, machineID: identity.machine,
                platformUUID: identity.platform, appVersion: identity.version,
                deviceToken: loadSecret(account: tokenAccount(for: id)))
            serverReachable = true
            switch response.status {
            case .valid:
                isLicensed = true
                updateAvailable = response.updateAvailable
                lastServerMessage = nil
                if response.deviceTokenRequired == true {
                    // Token rejected (rotated/expired) — re-activate silently is
                    // impossible without email; surface it once.
                    lastServerMessage = "License needs re-activation on this Mac."
                    isLicensed = false
                }
            case .revoked:
                isLicensed = false
                lastServerMessage = "This license has been revoked."
            case .expired:
                isLicensed = false
                lastServerMessage = "This license has expired."
            case .activationLimitReached:
                isLicensed = false
                lastServerMessage = response.message
            case .unknown:
                isLicensed = false
                lastServerMessage = "This Mac isn't activated. Activate to unlock cleanup."
            }
        } catch let error as LicenseServer.ServerError {
            _ = handleServerError(error, context: "validation")
        } catch {
            startGrace()
            lastServerMessage = "Couldn't reach the license server — offline grace active."
        }
    }

    // MARK: Deactivation (server §10, best-effort then local clear)

    func deactivateOnline() async {
        guard let id = storedLicenseID() else {
            clearLocalLicense()
            return
        }
        isWorking = true
        defer { isWorking = false }
        let server = LicenseServer(baseURL: serverBaseURL)
        let identity = Self.identity()
        if let token = loadSecret(account: tokenAccount(for: id)) {
            _ = try? await server.deactivate(licenseID: id, hardwareHash: identity.hash, deviceToken: token)
        }
        clearLocalLicense()
        lastServerMessage = "License deactivated on this Mac."
    }

    func deactivate() {
        Task { await deactivateOnline() }
    }

    // MARK: Offline grace (spec §85)

    @discardableResult
    private func handleServerError(_ error: LicenseServer.ServerError, context: String) -> Bool {
        switch error {
        case .offline:
            serverReachable = false
            startGrace()
            lastServerMessage = "Server unreachable during \(context) — offline grace started (\(graceDays) days, full features)."
            return true
        case .rejected(_, let message):
            serverReachable = true
            lastServerMessage = message
            return false
        case .invalidResponse:
            serverReachable = true
            lastServerMessage = "Unexpected server response during \(context)."
            return false
        }
    }

    private func startGrace() {
        if UserDefaults.standard.object(forKey: graceStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: graceStartKey)
        }
        refresh()
    }

    private func clearLocalLicense() {
        if let id = storedLicenseID() {
            deleteSecret(account: tokenAccount(for: id))
        }
        deleteSecret(account: "DiskBuddyLicenseID")
        deleteSecret(account: "DiskBuddyLicenseEmail")
        deleteSecret(account: "DiskBuddyLicenseKey") // legacy single-key item
        isLicensed = false
    }

    private func storedLicenseID() -> String? {
        loadSecret(account: "DiskBuddyLicenseID")
    }

    // MARK: Machine identity for this Mac

    private struct Identity {
        let hash: String
        let machine: String
        let platform: String
        let version: String
    }

    private static func identity() -> Identity {
        Identity(
            hash: MachineIdentity.hardwareHash(),
            machine: MachineIdentity.machineID(),
            platform: MachineIdentity.platformUUID() ?? MachineIdentity.machineID(),
            version: MachineIdentity.appVersion())
    }

    // MARK: Local format pre-checks (mirror server validation.ts)

    private static func isPlausibleLicenseID(_ id: String) -> Bool {
        guard (1...128).contains(id.count) else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber || "._:-".contains($0) }
    }

    private static func isPlausibleEmail(_ email: String) -> Bool {
        guard (3...320).contains(email.count), !email.contains(" ") else { return false }
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    // MARK: Keychain (id, email, per-license device token)

    private func tokenAccount(for licenseID: String) -> String {
        "diskbuddy.deviceToken.\(licenseID)"
    }

    private func saveSecret(_ value: String, account: String) {
        deleteSecret(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "DiskBuddy",
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "DiskBuddy",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: "DiskBuddy",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
