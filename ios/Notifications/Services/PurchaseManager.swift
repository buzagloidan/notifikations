import Foundation
import RevenueCat

// MARK: - PurchaseManager

/// Central purchase manager. Observes RevenueCat customer info and exposes
/// entitlement state to the SwiftUI view hierarchy via @EnvironmentObject.
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    /// The RevenueCat entitlement that gates "Pro" features.
    static let entitlementID = "Notifikations Pro"

    @Published private(set) var isPro = false
    @Published private(set) var customerInfo: CustomerInfo?

    private init() {}

    // MARK: - Configuration

    /// Call once at app launch (before any UI is shown).
    static func configure() {
        #if DEBUG
        let infoKey = "RevenueCatAPIKeyDebug"
        #else
        let infoKey = "RevenueCatAPIKey"
        #endif
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !apiKey.isEmpty else {
            fatalError("Missing \(infoKey) in Info.plist — copy ios/Config/Secrets.xcconfig.example to Secrets.xcconfig and fill in your RevenueCat API keys.")
        }
        Purchases.configure(withAPIKey: apiKey)
        Purchases.logLevel = .warn
        Purchases.shared.delegate = CustomerInfoUpdater.shared
        UserDefaults.standard.set(Purchases.shared.appUserID, forKey: "rcAppUserID")
        Task { await PurchaseManager.shared.refreshCustomerInfo() }
    }

    // MARK: - Customer Info

    func refreshCustomerInfo() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        await apply(info)
    }

    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        await apply(info)
    }

    func currentOfferingForPaywall() async throws -> Offering {
        let offerings = try await Purchases.shared.offerings()

        guard let offering = offerings.current else {
            throw PurchaseConfigurationError.noCurrentOffering
        }

        guard !offering.availablePackages.isEmpty else {
            throw PurchaseConfigurationError.emptyCurrentOffering(identifier: offering.identifier)
        }

        return offering
    }

    @MainActor
    func apply(_ info: CustomerInfo) {
        customerInfo = info
        let newIsPro = info.entitlements[Self.entitlementID]?.isActive == true
        if newIsPro != isPro {
            isPro = newIsPro
            Task { await APIService.shared.updateProStatus(isPro: newIsPro) }
        } else {
            isPro = newIsPro
        }
    }
}

enum PurchaseConfigurationError: LocalizedError {
    case noCurrentOffering
    case emptyCurrentOffering(identifier: String)

    var errorDescription: String? {
        switch self {
        case .noCurrentOffering:
            return "RevenueCat does not have a current offering for this app. Create an offering, add your monthly/yearly packages to it, and mark it as the default offering."
        case .emptyCurrentOffering(let identifier):
            return "The current RevenueCat offering (\(identifier)) has no available packages. Add your App Store subscriptions to packages inside that offering."
        }
    }
}

enum PurchaseErrorFormatter {
    static func message(from error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        let nsError = error as NSError
        let readableCode =
            (nsError.userInfo["readable_error_code"] as? String) ??
            (nsError.userInfo["rc_code_name"] as? String)
        let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String
        let underlyingDescription =
            (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription

        var messages: [String] = []

        for value in [nsError.localizedDescription, debugDescription, underlyingDescription] {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !messages.contains(trimmed) else { continue }
            messages.append(trimmed)
        }

        if let readableCode, !messages.contains("Code: \(readableCode)") {
            messages.append("Code: \(readableCode)")
        }

        return messages.isEmpty
            ? "RevenueCat returned an unknown purchase configuration error."
            : messages.joined(separator: "\n\n")
    }
}

// MARK: - Delegate

/// Receives push-based customer info updates from RevenueCat.
private final class CustomerInfoUpdater: NSObject, PurchasesDelegate {
    static let shared = CustomerInfoUpdater()

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { await PurchaseManager.shared.apply(customerInfo) }
    }
}
