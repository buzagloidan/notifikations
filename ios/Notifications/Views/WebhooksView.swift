import SwiftUI
import UserNotifications
import RevenueCat
import RevenueCatUI

enum WebhookTarget: String, CaseIterable {
    case device = "This Device"
    case all    = "All Devices"
}

struct MainView: View {
    @Namespace private var namespace
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var purchases: PurchaseManager

    @State private var target: WebhookTarget = .device
    @State private var isSendingTest = false
    @State private var showShare    = false
    @State private var shareContent = ""
    @State private var copied       = false
    @State private var showHistory  = false
    @State private var showSettings = false
    @State private var sendTestBurstTrigger = 0
    @State private var safariURL: URL? = nil
    @State private var notificationsBlocked = false
    @State private var showPaywall = false
    @State private var paywallError: String?
    @State private var paywallOffering: Offering?

    @AppStorage("trialStartDate") private var trialStartDateRaw: Double = 0

    private let secrets = SecretManager.shared
    private let baseURL = Config.apiV1

    private var trialEndDate: Date {
        Date(timeIntervalSince1970: trialStartDateRaw).addingTimeInterval(14 * 24 * 60 * 60)
    }

    private var trialExpired: Bool { Date() > trialEndDate }

    private var showTrialBanner: Bool { !purchases.isPro }

    var currentURL: String {
        baseURL + (target == .device ? secrets.deviceSecret : secrets.userSecret)
    }

    var currentSecret: String {
        target == .device ? secrets.deviceSecret : secrets.userSecret
    }

    var currentCURL: String {
        "curl -X POST \(currentURL) -d 'Hello world! 👋'"
    }

    func copyToClipboard(_ string: String) {
        UIPasteboard.general.string = string
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(duration: 0.25)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }

    func share(_ string: String) {
        shareContent = string
        showShare = true
    }

    private func sendTest() async {
        guard !isSendingTest, let url = URL(string: currentURL) else { return }
        isSendingTest = true
        defer { isSendingTest = false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "Hello world! 👋".data(using: .utf8)
        guard
            let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode)
        else { return }
        await MainActor.run {
            sendTestBurstTrigger += 1
        }
    }

    private func preparePaywall() async {
        do {
            paywallOffering = try await purchases.currentOfferingForPaywall()
            showPaywall = true
        } catch {
            paywallOffering = nil
            paywallError = PurchaseErrorFormatter.message(from: error)
        }
    }

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // ── Top icon buttons ──────────────────────────────────────
                if #available(iOS 26, macOS 26, *) {
                    GlassEffectContainer {
                        HStack {
                            Button { showHistory = true } label: {
                                NavCircleButton(icon: "clock.arrow.circlepath")
                            }
                            .matchedTransitionSource(id: "history", in: namespace)
                            Spacer()
                            Button { showSettings = true } label: {
                                NavCircleButton(icon: "gearshape")
                            }
                            .matchedTransitionSource(id: "settings", in: namespace)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                } else {
                    HStack {
                        Button { showHistory = true } label: {
                            NavCircleButton(icon: "clock.arrow.circlepath")
                        }
                        .matchedTransitionSource(id: "history", in: namespace)
                        Spacer()
                        Button { showSettings = true } label: {
                            NavCircleButton(icon: "gearshape")
                        }
                        .matchedTransitionSource(id: "settings", in: namespace)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Spacer()

                // ── Hero content ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 22) {
                    // Title
                    (
                        Text("Welcome\nto ").foregroundStyle(Color.appDark)
                        + Text("Notifikations").foregroundStyle(Color.appSage)
                    )
                    .font(.custom("Fraunces", size: 52))
                    .lineSpacing(2)

                    // Subtitle
                    Text("Send a notifikation to this device with a simple API call below.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appDark.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)

                    // Device selector
                    WebhookTargetPicker(target: $target)

                    // Code card
                    CodeCard(
                        url: currentURL,
                        isSending: isSendingTest,
                        burstTrigger: sendTestBurstTrigger,
                        onSendTest: { Task { await sendTest() } }
                    )

                    // Action buttons
                    HStack(spacing: 12) {
                        Menu {
                            Button { copyToClipboard(currentSecret) } label: {
                                Label("Copy Secret", systemImage: "key")
                            }
                            Button { copyToClipboard(currentURL) } label: {
                                Label("Copy URL", systemImage: "link")
                            }
                            Button { copyToClipboard(currentCURL) } label: {
                                Label("Copy cURL", systemImage: "terminal")
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(copied ? "Copied!" : "Copy").fontWeight(.semibold)
                                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 15))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(copied ? Color.appDark : Color.appSage,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(Color.appCream)
                        }

                        Menu {
                            Button { share(currentSecret) } label: {
                                Label("Share Secret", systemImage: "key")
                            }
                            Button { share(currentURL) } label: {
                                Label("Share URL", systemImage: "link")
                            }
                            Button { share(currentCURL) } label: {
                                Label("Share cURL", systemImage: "terminal")
                            }
                        } label: {
                            if #available(iOS 26, macOS 26, *) {
                                HStack(spacing: 8) {
                                    Text("Share").fontWeight(.semibold)
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                                .foregroundStyle(Color.appDark)
                            } else {
                                HStack(spacing: 8) {
                                    Text("Share").fontWeight(.semibold)
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.appDark.opacity(0.25), lineWidth: 1.5)
                                )
                                .foregroundStyle(Color.appDark)
                            }
                        }
                    }

                    // Read docs link
                    Button {
                        safariURL = URL(string: Config.docsURL)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Read docs")
                                .font(.system(size: 15, weight: .medium))
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(Color.appDark.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 48)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if showTrialBanner {
                TrialBannerView(
                    trialEndDate: trialEndDate,
                    expired: trialExpired,
                    onTap: {
                        Task { await preparePaywall() }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
        .sheet(isPresented: $showShare)    { ShareSheet(items: [shareContent]) }
        .sheet(isPresented: $showHistory) {
            HistoryView()
                .navigationTransition(.zoom(sourceID: "history", in: namespace))
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                .navigationTransition(.zoom(sourceID: "settings", in: namespace))
        }
        .sheet(isPresented: $showPaywall) {
            if let paywallOffering {
                PaywallView(offering: paywallOffering)
                    .onPurchaseCompleted { _ in showPaywall = false }
                    .onRestoreCompleted { _ in showPaywall = false }
            } else {
                ProgressView()
                    .presentationDetents([.medium])
            }
        }
        .fullScreenCover(isPresented: $notificationsBlocked) {
            NotificationsBlockerView(onPermissionGranted: {
                Task { await checkNotificationStatus() }
            })
        }
        .alert("Subscription Unavailable", isPresented: Binding(
            get: { paywallError != nil },
            set: { if !$0 { paywallError = nil } }
        )) {
            Button("OK", role: .cancel) { paywallError = nil }
        } message: {
            Text(paywallError ?? "")
        }
        .task {
            if trialStartDateRaw == 0 {
                trialStartDateRaw = Date().timeIntervalSince1970
            }
            await checkNotificationStatus()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await checkNotificationStatus() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await checkNotificationStatus() }
        }
    }

    private func checkNotificationStatus() async {
        let center = UNUserNotificationCenter.current()
        #if targetEnvironment(macCatalyst)
        // On Mac Catalyst the OS caches a stale .denied status after the user
        // re-enables the app in System Settings. Calling requestAuthorization
        // forces the daemon to re-evaluate and updates the cached value.
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        #endif
        let settings = await center.notificationSettings()
        await MainActor.run {
            notificationsBlocked = settings.authorizationStatus == .denied
        }
    }
}

// MARK: - Nav circle button

struct NavCircleButton: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.appDark)
            .frame(width: 44, height: 44)
            .glassCircleButton()
    }
}

// MARK: - Target picker

struct WebhookTargetPicker: View {
    @Binding var target: WebhookTarget

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WebhookTarget.allCases, id: \.self) { option in
                Button {
                    withAnimation(.spring(duration: 0.25)) { target = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            target == option
                                ? Color.appCream
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(
                            target == option ? Color.appDark : Color.appDark.opacity(0.45)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - Code card

struct CodeCard: View {
    let url: String
    var isSending: Bool = false
    var burstTrigger: Int = 0
    let onSendTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Bash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appDark)
                Spacer()
                Button(action: onSendTest) {
                    HStack(spacing: 5) {
                        if isSending {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Color.appDark)
                        } else {
                            Text("Send Test")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundStyle(Color.appDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minWidth: 80)
                    .glassCapsuleButton()
                    .overlay {
                        EmojiBurstOverlay(trigger: burstTrigger)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .animation(.default, value: isSending)
            }

            (
                Text("curl -X POST ").foregroundStyle(Color.appDark)
                + Text(url).foregroundStyle(Color.appSage)
                + Text("\n  -d ").foregroundStyle(Color.appDark)
                + Text("'Hello world! 👋'").foregroundStyle(Color.appDark.opacity(0.55))
            )
            .font(.system(size: 13, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
    }
}

private struct EmojiBurstParticle: Identifiable {
    let id = UUID()
    let emoji: String
    let x: CGFloat
    let y: CGFloat
    let delay: Double
    let rotation: Double
    let size: CGFloat
}

private struct EmojiBurstOverlay: View {
    let trigger: Int

    @State private var particles: [EmojiBurstParticle] = []
    @State private var animate = false

    private let emojis = ["🎉", "✨", "🎊", "🚀", "🔥", "💫", "🤩", "🥳", "🙌", "✅"]

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Text(particle.emoji)
                    .font(.system(size: particle.size))
                    .offset(x: animate ? particle.x : 0, y: animate ? particle.y : 0)
                    .scaleEffect(animate ? 0.65 : 0.2)
                    .rotationEffect(.degrees(animate ? particle.rotation : 0))
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.75).delay(particle.delay),
                        value: animate
                    )
            }
        }
        .frame(width: 130, height: 130)
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            burst()
        }
    }

    private func burst() {
        particles = (0..<14).map { _ in
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 28...78)
            return EmojiBurstParticle(
                emoji: emojis.randomElement() ?? "🎉",
                x: cos(angle) * distance,
                y: sin(angle) * distance,
                delay: Double.random(in: 0...0.12),
                rotation: Double.random(in: -35...35),
                size: CGFloat.random(in: 14...21)
            )
        }

        animate = false
        DispatchQueue.main.async {
            animate = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            particles = []
            animate = false
        }
    }
}

// MARK: - Trial Banner

struct TrialBannerView: View {
    let trialEndDate: Date
    let expired: Bool
    let onTap: () -> Void

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM yyyy"
        return fmt.string(from: trialEndDate)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: expired ? "lock.fill" : "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appSage)

                VStack(alignment: .leading, spacing: 2) {
                    if expired {
                        Text("Your free trial has ended.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appDark)
                        Text("Subscribe to keep receiving pushes.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appDark.opacity(0.65))
                    } else {
                        Text("Free access ends \(formattedDate).")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appDark)
                        Text("Subscribe before then to keep pushes coming.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appDark.opacity(0.65))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appDark.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

// ShareSheet lives in WebhookRow.swift
