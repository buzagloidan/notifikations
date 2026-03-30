import SwiftUI
import UIKit
import UserNotifications

struct NotificationsBlockerView: View {
    let onPermissionGranted: () -> Void

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 22) {
                    (
                        Text("Welcome\nto ").foregroundStyle(Color.appDark)
                        + Text("Notifikations").foregroundStyle(Color.appSage)
                    )
                    .font(.custom("Fraunces", size: 52))
                    .lineSpacing(2)

                    Text("Notifications are turned off. Turn them on to receive notifications on this device.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appDark.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        #if targetEnvironment(macCatalyst)
                        let urlString = "x-apple.systempreferences:com.apple.preference.notifications"
                        #else
                        let urlString = UIApplication.openNotificationSettingsURLString
                        #endif
                        if let url = URL(string: urlString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text("Open Settings")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 17))
                        }
                        .foregroundStyle(Color.appCream)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(Color.appSage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 48)
            }
        }
        .task {
            await pollUntilGranted()
        }
    }

    private func pollUntilGranted() async {
        let center = UNUserNotificationCenter.current()
        while true {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await center.notificationSettings()
            if settings.authorizationStatus != .denied {
                onPermissionGranted()
                return
            }
        }
    }
}
