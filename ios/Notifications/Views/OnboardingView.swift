import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isRequesting = false

    private let features: [(icon: String, text: String)] = [
        ("bolt.fill",        "Instant delivery to this device"),
        ("terminal.fill",    "Simple REST API — no SDK needed"),
        ("bell.badge.fill",  "Custom sounds & rich notifications"),
    ]

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 28) {
                    // Title
                    (
                        Text("Welcome\nto ").foregroundStyle(Color.appDark)
                        + Text("Notifikations").foregroundStyle(Color.appSage)
                    )
                    .font(.custom("Fraunces", size: 52))
                    .lineSpacing(2)

                    // Feature list
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(features, id: \.text) { feature in
                            HStack(spacing: 12) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.appSage)
                                    .frame(width: 24)
                                Text(feature.text)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.appDark.opacity(0.75))
                            }
                        }
                    }

                    // CTA
                    Button {
                        Task { await requestAndProceed() }
                    } label: {
                        HStack {
                            if isRequesting {
                                ProgressView()
                                    .tint(Color.appCream)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Enable Notifications")
                                    .font(.system(size: 17, weight: .semibold))
                                Spacer()
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 16))
                            }
                        }
                        .foregroundStyle(Color.appCream)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(Color.appSage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting)

                    Text("You can change this later in Settings.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appDark.opacity(0.35))
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 64)
            }
        }
    }

    private func requestAndProceed() async {
        isRequesting = true
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await MainActor.run {
            NotificationService.shared.registerForRemoteNotifications()
            hasCompletedOnboarding = true
        }
    }
}
