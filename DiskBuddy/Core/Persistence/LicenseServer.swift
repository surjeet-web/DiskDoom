import Foundation

// MARK: - License server client (Cloudflare Worker API, see server README)
//
// POST {base}/activate | validate | deactivate, GET {base}/health.
// Success DTOs mirror src/types.ts; failures decode {error, code, message}
// so the UI can show the server's own reason (email_mismatch,
// activation_limit, revoked, expired, …). Device tokens are opaque to us —
// stored in Keychain by LicenseStore, never logged.

actor LicenseServer {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    struct ValidationResponse: Codable, Sendable {
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

        enum Status: String, Codable, Sendable {
            case valid
            case revoked
            case activationLimitReached = "activation_limit_reached"
            case expired
            case unknown
        }
    }

    struct ActivationResponse: Codable, Sendable {
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

    struct DeactivationResponse: Codable, Sendable {
        let success: Bool
        let message: String
    }

    struct ServerErrorBody: Codable {
        let code: String
        let message: String
    }

    enum ServerError: Error, Sendable {
        case offline(underlying: Error)
        case rejected(code: String, message: String)
        case invalidResponse
    }

    func health() async throws {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ServerError.invalidResponse
        }
    }

    func activate(licenseID: String, email: String, hardwareHash: String, machineID: String, platformUUID: String, appVersion: String) async throws -> ActivationResponse {
        let body: [String: String] = [
            "license_id": licenseID,
            "email": email,
            "hardware_hash": hardwareHash,
            "machine_id": machineID,
            "platform_uuid": platformUUID,
            "app_version": appVersion,
        ]
        return try await post(path: "activate", body: body)
    }

    func validate(licenseID: String, hardwareHash: String, machineID: String, platformUUID: String, appVersion: String, deviceToken: String?) async throws -> ValidationResponse {
        var body: [String: String] = [
            "license_id": licenseID,
            "hardware_hash": hardwareHash,
            "machine_id": machineID,
            "platform_uuid": platformUUID,
            "app_version": appVersion,
        ]
        if let deviceToken { body["device_token"] = deviceToken }
        return try await post(path: "validate", body: body)
    }

    func deactivate(licenseID: String, hardwareHash: String, deviceToken: String) async throws -> DeactivationResponse {
        let body: [String: String] = [
            "license_id": licenseID,
            "hardware_hash": hardwareHash,
            "device_token": deviceToken,
        ]
        return try await post(path: "deactivate", body: body)
    }

    private func post<T: Decodable & Sendable>(path: String, body: [String: String]) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServerError.offline(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ServerError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let decoded = try? JSONDecoder().decode(ServerErrorBody.self, from: data) {
                throw ServerError.rejected(code: decoded.code, message: decoded.message)
            }
            throw ServerError.rejected(code: "http_\(http.statusCode)", message: String(data: data, encoding: .utf8) ?? "Server error")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ServerError.invalidResponse
        }
    }
}
