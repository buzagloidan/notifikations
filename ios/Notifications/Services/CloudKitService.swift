import CloudKit
import Foundation

/// Manages the user's private CloudKit database for cross-device secret sync.
///
/// - The user secret is shared across all of the user's devices (same iCloud account).
/// - Each device's secret is stored per-device so any device can list all registered webhooks.
/// - Raw secrets are stored in the CloudKit *private* database — inaccessible to the backend.
final class CloudKitService {
    static let shared = CloudKitService()
    private init() {}

    private lazy var container = CKContainer(identifier: "iCloud.com.idanbu.notifications")
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    private let recordType = "WebhookSecrets"
    private let userSecretField = "userSecret"
    private let deviceSecretsField = "deviceSecrets" // JSON-encoded [DeviceEntry]

    struct DeviceEntry: Codable {
        let deviceID: String
        let secret: String
        let label: String
    }

    // MARK: - User Secret

    /// Returns the shared user secret for this iCloud account.
    /// Creates and uploads one if this is the first device to register.
    func fetchOrCreateUserSecret() async throws -> String {
        let record = try await fetchSecretsRecord()

        if let record = record,
           let existing = record[userSecretField] as? String,
           !existing.isEmpty {
            return existing
        }

        // First device — generate and upload
        let newUserSecret = String.randomSecret(prefix: "ntf_usr_")
        let target = record ?? CKRecord(recordType: recordType)
        target[userSecretField] = newUserSecret as CKRecordValue
        // Preserve any existing device entries
        if record != nil && target[deviceSecretsField] == nil {
            target[deviceSecretsField] = "[]" as CKRecordValue
        }
        _ = try await privateDB.save(target)
        return newUserSecret
    }

    // MARK: - Device Secret Sync

    /// Saves (or updates) this device's secret entry in CloudKit.
    func saveDeviceSecret(_ secret: String, deviceID: String, label: String) async throws {
        let record = try await fetchSecretsRecord() ?? CKRecord(recordType: recordType)

        var entries = decodeDeviceEntries(from: record)
        entries.removeAll { $0.deviceID == deviceID }
        entries.append(DeviceEntry(deviceID: deviceID, secret: secret, label: label))

        record[deviceSecretsField] = encodeDeviceEntries(entries) as CKRecordValue
        _ = try await privateDB.save(record)
    }

    /// Removes this device's entry (called on unregister).
    func removeDeviceSecret(deviceID: String) async throws {
        guard let record = try await fetchSecretsRecord() else { return }

        var entries = decodeDeviceEntries(from: record)
        entries.removeAll { $0.deviceID == deviceID }
        record[deviceSecretsField] = encodeDeviceEntries(entries) as CKRecordValue
        _ = try await privateDB.save(record)
    }

    // MARK: - iCloud Availability

    /// Returns true if the CloudKit entitlement is present and the user is signed into iCloud.
    /// NOTE: Returns false unconditionally until the Apple Developer account and
    /// iCloud entitlements are configured. Re-enable the body below after enrollment.
    func isAvailable() async -> Bool {
        return false
        // TODO: uncomment after adding CloudKit entitlements (requires paid Apple Developer account)
        // guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        // do {
        //     let status = try await container.accountStatus()
        //     return status == .available
        // } catch {
        //     return false
        // }
    }

    // MARK: - Private Helpers

    private func fetchSecretsRecord() async throws -> CKRecord? {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let (matchResults, _) = try await privateDB.records(matching: query, resultsLimit: 1)
        return try matchResults.first?.1.get()
    }

    private func decodeDeviceEntries(from record: CKRecord) -> [DeviceEntry] {
        guard let json = record[deviceSecretsField] as? String,
              let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([DeviceEntry].self, from: data)
        else { return [] }
        return entries
    }

    private func encodeDeviceEntries(_ entries: [DeviceEntry]) -> String {
        guard let data = try? JSONEncoder().encode(entries),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }
}
