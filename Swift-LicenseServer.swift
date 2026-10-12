import Foundation
import Security

actor LicenseServer {
    static let shared = LicenseServer()

    private let baseURL = URL(string: "https://api.diskbuddy.com/v1")!

    struct ValidationResponse: Codable {
        let status: Status
        let activeMachines: Int
        let message: String
        let timestamp: String
        let updateAvailable: String?
        let claudeInsight: String?
        let deviceTokenRequired: Bool?

        enum CodingKeys: String, CodingKey {
            case status
            case activeMachines = "active_machines"
            case message
            case timestamp
            case updateAvailable = "update_available"
            case claudeInsight = "claude_insight"
            case deviceTokenRequired = "device_token_required"
        }

        enum Status: String, Codable {
            case valid
            case revoked
            case activationLimitReached = "activation_limit_reached"
            case expired
            case unknown
        }
    }

    struct ActivationResponse: Codable {
        let success: Bool
        let machineID: String
        let message: String
        let deviceToken: String?
        let claudeInsight: String?

        enum CodingKeys: String, CodingKey {
            case success
            case machineID = "machine_id"
            case message
            case deviceToken = "device_token"
            case claudeInsight = "claude_insight"
        }
    }

    struct DeactivationResponse: Codable {
        let success: Bool
        let message: String
    }

    enum ServerError: Error {
        case invalidResponse
        case http(Int, String)
    }

    func activate(
        licenseID: String,
        email: String,
        hardwareHash: String,
        machineID: String,
        platformUUID: String,
        appVersion: String
    ) async throws -> ActivationResponse {
        let body: [String: String] = [
            "license_id": licenseID,
            "email": email,
            "hardware_hash": hardwareHash,
            "machine_id": machineID,
            "platform_uuid": platformUUID,
            "app_version": appVersion
        ]

        let response: ActivationResponse = try await post(
            path: "activate",
            body: body
        )

        if let token = response.deviceToken {
            Keychain.set(token, for: "diskbuddy.deviceToken.\(licenseID)")
        }

        return response
    }

    func validate(
        licenseID: String,
        hardwareHash: String,
        machineID: String,
        platformUUID: String,
        appVersion: String
    ) async throws -> ValidationResponse {
        let token = Keychain.get("diskbuddy.deviceToken.\(licenseID)")

        let body: [String: String] = [
            "license_id": licenseID,
            "hardware_hash": hardwareHash,
            "machine_id": machineID,
            "platform_uuid": platformUUID,
            "app_version": appVersion
        ].merging(
            token.map { ["device_token": $0] } ?? [:],
            uniquingKeysWith: { _, new in new }
        )

        return try await post(path: "validate", body: body)
    }

    func deactivate(
        licenseID: String,
        hardwareHash: String
    ) async throws -> DeactivationResponse {
        guard let token = Keychain.get("diskbuddy.deviceToken.\(licenseID)") else {
            throw ServerError.invalidResponse
        }

        let body = [
            "license_id": licenseID,
            "hardware_hash": hardwareHash,
            "device_token": token
        ]

        let response: DeactivationResponse = try await post(
            path: "deactivate",
            body: body
        )

        if response.success {
            Keychain.delete("diskbuddy.deviceToken.\(licenseID)")
        }

        return response
    }

    private func post<T: Decodable>(
        path: String,
        body: [String: String]
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ServerError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "Server error"
            throw ServerError.http(http.statusCode, message)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
