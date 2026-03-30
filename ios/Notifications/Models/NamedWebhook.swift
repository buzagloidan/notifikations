import Foundation
import Security

enum WebhookScope: String, Codable, CaseIterable {
    case device
    case user

    var displayName: String {
        switch self {
        case .device: return "This Device"
        case .user:   return "All Devices"
        }
    }

    var systemImage: String {
        switch self {
        case .device: return "iphone"
        case .user:   return "person.2.fill"
        }
    }
}

struct NamedWebhook: Codable, Identifiable {
    let id: String          // stable UUID
    let secret: String      // raw secret — stored in Keychain, never leaves device
    var label: String
    var scope: WebhookScope
    let createdAt: Date

    var webhookDigest: String { secret.sha256Digest }
    var url: String { Config.apiV1 + secret }
    var curlString: String { "curl -X POST \(url) -d 'Hello world! 👋'" }
}

// MARK: - Manager

final class NamedWebhookManager: ObservableObject {
    static let shared = NamedWebhookManager()

    private let keychainKey = "com.notifications.named-webhooks"

    @Published private(set) var webhooks: [NamedWebhook] = []

    private init() {
        webhooks = loadFromKeychain()
    }

    // MARK: - Create

    func create(label: String, scope: WebhookScope) async throws -> NamedWebhook {
        guard let token = UserDefaults.standard.string(forKey: "apnsDeviceToken"),
              !token.isEmpty else {
            throw NamedWebhookError.notRegistered
        }

        let secret = String.randomSecret(prefix: "ntf_wh_")
        let webhook = NamedWebhook(
            id: UUID().uuidString,
            secret: secret,
            label: label,
            scope: scope,
            createdAt: Date()
        )

        try await APIService.shared.createNamedWebhook(
            deviceToken: token,
            webhookDigest: webhook.webhookDigest,
            label: label,
            scope: scope.rawValue
        )

        await MainActor.run {
            webhooks.append(webhook)
            saveToKeychain()
        }

        return webhook
    }

    // MARK: - Delete

    func delete(_ webhook: NamedWebhook) async throws {
        guard let token = UserDefaults.standard.string(forKey: "apnsDeviceToken"),
              !token.isEmpty else {
            throw NamedWebhookError.notRegistered
        }

        try await APIService.shared.deleteNamedWebhook(
            deviceToken: token,
            webhookDigest: webhook.webhookDigest
        )

        await MainActor.run {
            webhooks.removeAll { $0.id == webhook.id }
            saveToKeychain()
        }
    }

    // MARK: - Keychain persistence

    private func saveToKeychain() {
        guard let data = try? JSONEncoder().encode(webhooks) else { return }
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain() -> [NamedWebhook] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let stored = try? JSONDecoder().decode([NamedWebhook].self, from: data) else {
            return []
        }
        return stored
    }
}

// MARK: - Errors

enum NamedWebhookError: LocalizedError {
    case notRegistered

    var errorDescription: String? {
        "Device not yet registered. Please relaunch the app and try again."
    }
}
