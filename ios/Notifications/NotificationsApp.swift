import SwiftUI
import SwiftData
import SafariServices

@main
struct NotificationsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var purchases = PurchaseManager.shared
    private let container: ModelContainer

    init() {
        // History is device-only — disable CloudKit sync to avoid the
        // "all attributes must be optional" CloudKit requirement.
        let config = ModelConfiguration(cloudKitDatabase: .none)
        if let c = try? ModelContainer(for: NotificationRecord.self, configurations: config) {
            container = c
        } else {
            // Existing store is in a bad state — wipe it and start fresh.
            // (History was never saving anyway, so no data is lost.)
            if let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                for name in ["default.store", "default.store-shm", "default.store-wal"] {
                    try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
                }
            }
            container = try! ModelContainer(for: NotificationRecord.self, configurations: config)
        }
        NotificationService.shared.modelContext = ModelContext(container)

        // Configure RevenueCat as early as possible.
        PurchaseManager.configure()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainView()
                    .modelContainer(container)
                    .environmentObject(purchases)
                    .preferredColorScheme(.light)
            } else {
                OnboardingView()
                    .environmentObject(purchases)
                    .preferredColorScheme(.light)
            }
        }
    }
}

// MARK: - Brand colors

extension Color {
    /// #696F7B — slate, primary text + icons
    static let appDark    = Color(red: 0.412, green: 0.435, blue: 0.482)
    /// #FFAE53 — amber, accent / app name / Copy button
    static let appSage    = Color(red: 1.0,   green: 0.682, blue: 0.325)
    /// #F2EAE0 — warm sand, card / code block surfaces
    static let appTan     = Color(red: 0.949, green: 0.918, blue: 0.878)
    /// #FBF8F5 — warm white, page background
    static let appCream   = Color(red: 0.984, green: 0.973, blue: 0.961)
    /// #FF5500 — orange-red, used for "copied" confirmations
    static let appGreen   = Color(red: 1.0,   green: 0.333, blue: 0.0)
}

// MARK: - Liquid Glass helpers (iOS 26+)

extension View {
    /// Non-interactive glass card — Liquid Glass on iOS 26+, appTan surface on earlier OS.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat, fallbackOpacity: Double = 1.0) -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(Color.appTan.opacity(fallbackOpacity),
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// Interactive glass circle — Liquid Glass on iOS 26+, appTan circle on earlier OS.
    @ViewBuilder
    func glassCircleButton() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self.background(Color.appTan, in: Circle())
        }
    }

    /// Interactive glass capsule — for pill-shaped action buttons.
    @ViewBuilder
    func glassCapsuleButton() -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(Capsule().stroke(Color.appDark.opacity(0.3), lineWidth: 1))
        }
    }

    /// Interactive glass rounded rect — for small icon buttons.
    @ViewBuilder
    func glassIconButton(cornerRadius: CGFloat = 8) -> some View {
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(Color.appTan, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - In-app browser

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
