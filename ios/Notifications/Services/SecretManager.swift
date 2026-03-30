import Foundation
import Security
import UIKit

/// Manages the two persistent webhook secrets.
///
/// - `deviceSecret`  (ntf_dev_…) — unique to this device, stored in Keychain + CloudKit private DB
/// - `userSecret`    (ntf_usr_…) — shared across all user's devices, sourced from CloudKit
final class SecretManager: ObservableObject {
    static let shared = SecretManager()

    private let deviceSecretKey = "com.notifications.secret.device"
    private let userSecretKey   = "com.notifications.secret.user"

    @Published private(set) var deviceSecret: String
    @Published private(set) var userSecret: String

    private init() {
        deviceSecret = SecretManager.loadStatic(key: "com.notifications.secret.device")
            ?? SecretManager.generateStatic(prefix: "ntf_dev_", key: "com.notifications.secret.device")
        userSecret = SecretManager.loadStatic(key: "com.notifications.secret.user")
            ?? SecretManager.generateStatic(prefix: "ntf_usr_", key: "com.notifications.secret.user")
    }

    // MARK: - CloudKit Sync

    /// Call once on app launch (after CloudKit availability check).
    /// Fetches the shared user secret from CloudKit and caches it in Keychain,
    /// then syncs this device's secret up to CloudKit.
    func syncWithCloudKit() async {
        guard await CloudKitService.shared.isAvailable() else { return }

        do {
            // Fetch (or create) the shared user secret from CloudKit
            let cloudUserSecret = try await CloudKitService.shared.fetchOrCreateUserSecret()

            // If CloudKit has a user secret different from Keychain, trust CloudKit
            let localUserSecret = load(key: userSecretKey)
            if localUserSecret == nil || localUserSecret != cloudUserSecret {
                save(key: userSecretKey, value: cloudUserSecret)
                await MainActor.run { userSecret = cloudUserSecret }
            }

            // Sync this device's secret up to CloudKit
            let deviceID = UIDeviceIdentifier.current
            let label = await MainActor.run { deviceLabel() }
            try await CloudKitService.shared.saveDeviceSecret(
                deviceSecret, deviceID: deviceID, label: label
            )
        } catch {
            // CloudKit sync is best-effort; app functions fine with local Keychain only
        }
    }

    // MARK: - Rotation

    func rotateDeviceSecret() -> String {
        let new = String.randomSecret(prefix: "ntf_dev_")
        save(key: deviceSecretKey, value: new)
        deviceSecret = new
        Task {
            guard await CloudKitService.shared.isAvailable() else { return }
            let deviceID = UIDeviceIdentifier.current
            let label = await MainActor.run { deviceLabel() }
            try? await CloudKitService.shared.saveDeviceSecret(new, deviceID: deviceID, label: label)
        }
        return new
    }

    func rotateUserSecret() -> String {
        let new = String.randomSecret(prefix: "ntf_usr_")
        setUserSecret(new)
        return new
    }

    func setUserSecret(_ newSecret: String) {
        save(key: userSecretKey, value: newSecret)
        userSecret = newSecret
    }

    // MARK: - Private

    private func generate(prefix: String, key: String) -> String {
        let secret = String.randomSecret(prefix: prefix)
        save(key: key, value: secret)
        return secret
    }

    private func load(key: String) -> String? {
        SecretManager.loadStatic(key: key)
    }

    private static func loadStatic(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func generateStatic(prefix: String, key: String) -> String {
        let secret = String.randomSecret(prefix: prefix)
        guard let data = secret.data(using: .utf8) else { return secret }
        let deleteQuery: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
        SecItemDelete(deleteQuery as CFDictionary)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        return secret
    }

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrAccount:    key,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    @MainActor
    private func deviceLabel() -> String {
        #if targetEnvironment(macCatalyst)
        return ProcessInfo.processInfo.hostName
        #else
        return UIDevice.current.name
        #endif
    }
}

/// Stable per-device identifier stored in Keychain (survives app reinstalls on same device).
enum UIDeviceIdentifier {
    static var current: String {
        let key = "com.notifications.device.id"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let newID = UUID().uuidString
        if let data = newID.data(using: .utf8) {
            let addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: key,
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
        return newID
    }
}
