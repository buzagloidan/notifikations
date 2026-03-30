import UIKit
import UserNotifications
import SwiftData

/// Handles APNs registration and incoming notification processing.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private override init() { super.init() }

    // Set by the app container after SwiftData is ready
    var modelContext: ModelContext?

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
    }

    private func registerNotificationCategories() {
        let yes      = UNNotificationAction(identifier: "YES",     title: "Yes",     options: [])
        let no       = UNNotificationAction(identifier: "NO",      title: "No",      options: [.destructive])
        let approve  = UNNotificationAction(identifier: "APPROVE", title: "Approve", options: [])
        let dismiss  = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [.destructive])
        let confirm  = UNNotificationAction(identifier: "CONFIRM", title: "Confirm", options: [])

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: "YES_NO",          actions: [yes, no],          intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "APPROVE_DISMISS", actions: [approve, dismiss], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "CONFIRM",         actions: [confirm],          intentIdentifiers: [], options: []),
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func registerForRemoteNotifications() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // Called when app receives a notification while in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        saveRecord(from: notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    // Called when user taps a notification or action button
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        saveRecord(from: userInfo)

        let actionIdentifier = response.actionIdentifier
        let isCustomAction = actionIdentifier != UNNotificationDefaultActionIdentifier
                          && actionIdentifier != UNNotificationDismissActionIdentifier

        if isCustomAction,
           let callbackURLString = userInfo["callback_url"] as? String,
           let callbackURL = URL(string: callbackURLString) {
            sendCallback(to: callbackURL, action: actionIdentifier.lowercased(), completion: completionHandler)
            return
        }

        if actionIdentifier == UNNotificationDefaultActionIdentifier,
           let urlString = userInfo["open_url"] as? String,
           let url = URL(string: urlString) {
            Task { @MainActor in UIApplication.shared.open(url) }
        }
        completionHandler()
    }

    private func sendCallback(to url: URL, action: String, completion: @escaping () -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action])
        URLSession.shared.dataTask(with: request) { _, _, _ in completion() }.resume()
    }

    func saveRecord(from userInfo: [AnyHashable: Any]) {
        let shouldSave = UserDefaults.standard.object(forKey: "notifHistoryEnabled") as? Bool ?? true
        guard shouldSave,
              let record = NotificationRecord.from(userInfo: userInfo),
              let ctx = modelContext else { return }
        Task { @MainActor in
            ctx.insert(record)
            try? ctx.save()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.shared.setup()
        Task {
            // Sync user secret from CloudKit before registering with backend
            await SecretManager.shared.syncWithCloudKit()
            // Only request permission if onboarding is already complete.
            // First-time users see the permission prompt inside OnboardingView.
            let isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            if isOnboarded {
                await NotificationService.shared.requestPermission()
            }
            NotificationService.shared.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(tokenString, forKey: "apnsDeviceToken")
        let rcUserId = UserDefaults.standard.string(forKey: "rcAppUserID")
        Task {
            do {
                try await APIService.shared.register(deviceToken: tokenString, rcUserId: rcUserId)
                print("[Notifications] APNs token registered with backend.")
            } catch {
                print("[Notifications] Backend registration failed: \(error.localizedDescription)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Notifications] Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationService.shared.saveRecord(from: userInfo)
        completionHandler(.newData)
    }
}
