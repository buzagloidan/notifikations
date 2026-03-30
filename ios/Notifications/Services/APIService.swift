import Foundation
import UIKit

/// Communicates with the Notifications backend API.
final class APIService {
    static let shared = APIService()
    private init() {}

    private let baseURL = Config.apiBase

    struct RegisterRequest: Encodable {
        let deviceToken: String
        let deviceDigest: String
        let userDigest: String
        let label: String
        let rcUserId: String?
    }

    struct RotateRequest: Encodable {
        let oldDigest: String
        let newDigest: String
        let deviceToken: String
    }

    struct RotateUserRequest: Encodable {
        let oldUserDigest: String
        let newUserDigest: String
        let deviceDigest: String
        let deviceToken: String
    }

    struct UnregisterRequest: Encodable {
        let deviceDigest: String
        let deviceToken: String
    }

    struct APIErrorBody: Decodable {
        let error: String?
        let reason: String?
        let message: String?
        let statusCode: Int?
        let host: String?
    }

    enum APIError: LocalizedError {
        case invalidResponse
        case http(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid server response."
            case .http(let statusCode, let message):
                return "HTTP \(statusCode): \(message)"
            }
        }
    }

    // MARK: - Register

    func register(deviceToken: String, label: String? = nil, rcUserId: String? = nil) async throws {
        #if targetEnvironment(macCatalyst)
        let deviceName = ProcessInfo.processInfo.hostName
        #else
        let deviceName = await MainActor.run { UIDevice.current.name }
        #endif
        let resolvedLabel = label ?? deviceName
        let secrets = SecretManager.shared
        let body = RegisterRequest(
            deviceToken: deviceToken,
            deviceDigest: secrets.deviceSecret.sha256Digest,
            userDigest: secrets.userSecret.sha256Digest,
            label: resolvedLabel,
            rcUserId: rcUserId
        )
        try await post(path: "/api/v1/register", body: body)
    }

    // MARK: - Rotate

    func rotateDeviceSecret(deviceToken: String, oldSecret: String) async throws -> String {
        let newSecret = SecretManager.shared.rotateDeviceSecret()
        let body = RotateRequest(
            oldDigest: oldSecret.sha256Digest,
            newDigest: newSecret.sha256Digest,
            deviceToken: deviceToken
        )
        try await post(path: "/api/v1/rotate", body: body)
        return newSecret
    }

    func rotateUserSecret(
        deviceToken: String,
        deviceSecret: String,
        oldUserSecret: String
    ) async throws -> String {
        let newUserSecret = String.randomSecret(prefix: "ntf_usr_")
        let body = RotateUserRequest(
            oldUserDigest: oldUserSecret.sha256Digest,
            newUserDigest: newUserSecret.sha256Digest,
            deviceDigest: deviceSecret.sha256Digest,
            deviceToken: deviceToken
        )
        try await post(path: "/api/v1/rotate-user", body: body)
        SecretManager.shared.setUserSecret(newUserSecret)
        return newUserSecret
    }

    // MARK: - Pro Status Sync

    func updateProStatus(isPro: Bool) async {
        guard let deviceToken = UserDefaults.standard.string(forKey: "apnsDeviceToken"),
              !deviceToken.isEmpty else { return }
        struct Body: Encodable {
            let deviceDigest: String
            let deviceToken: String
            let isPro: Bool
        }
        let body = Body(
            deviceDigest: SecretManager.shared.deviceSecret.sha256Digest,
            deviceToken: deviceToken,
            isPro: isPro
        )
        try? await post(path: "/api/v1/update-status", body: body)
    }

    // MARK: - Named Webhooks

    func createNamedWebhook(
        deviceToken: String,
        webhookDigest: String,
        label: String,
        scope: String
    ) async throws {
        struct Body: Encodable {
            let deviceDigest: String
            let deviceToken: String
            let webhookDigest: String
            let label: String
            let scope: String
        }
        let body = Body(
            deviceDigest: SecretManager.shared.deviceSecret.sha256Digest,
            deviceToken: deviceToken,
            webhookDigest: webhookDigest,
            label: label,
            scope: scope
        )
        try await post(path: "/api/v1/webhooks", body: body)
    }

    func deleteNamedWebhook(deviceToken: String, webhookDigest: String) async throws {
        struct Body: Encodable {
            let deviceDigest: String
            let deviceToken: String
        }
        let body = Body(
            deviceDigest: SecretManager.shared.deviceSecret.sha256Digest,
            deviceToken: deviceToken
        )
        try await delete(path: "/api/v1/webhooks/\(webhookDigest)", body: body)
    }

    // MARK: - Unregister

    func unregister(secret: String, deviceToken: String) async throws {
        let body = UnregisterRequest(deviceDigest: secret.sha256Digest, deviceToken: deviceToken)
        try await delete(path: "/api/v1/unregister", body: body)
    }

    // MARK: - Helpers

    private func post<T: Encodable>(path: String, body: T) async throws {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func delete<T: Encodable>(path: String, body: T) async throws {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.http(
                statusCode: http.statusCode,
                message: parseErrorMessage(from: data)
            )
        }
    }

    private func parseErrorMessage(from data: Data) -> String {
        if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) {
            var parts: [String] = []
            if let error = body.error, !error.isEmpty { parts.append(error) }
            if let reason = body.reason, !reason.isEmpty, reason != body.error { parts.append(reason) }
            if let host = body.host, !host.isEmpty { parts.append("host=\(host)") }
            if !parts.isEmpty { return parts.joined(separator: " | ") }
        }

        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }

        return "Request failed."
    }
}
