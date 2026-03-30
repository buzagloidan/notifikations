import SwiftUI
import SwiftData
import StoreKit
import RevenueCat
import RevenueCatUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var purchases: PurchaseManager

    @State private var showTest            = false
    @State private var showPaywall         = false
    @State private var showCustomerCenter  = false
    @State private var isRestoring         = false
    @State private var restoreError: String?
    @State private var paywallError: String?
    @State private var paywallOffering: Offering?
    @State private var safariURL: URL?     = nil

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {

                    // ── Pro Banner / Subscription Management ──────────────
                    if purchases.isPro {
                        ProActiveCard(onManage: { showCustomerCenter = true })
                    } else {
                        ProUpgradeCard(
                            isRestoring: isRestoring,
                            onUpgrade: {
                                Task { await preparePaywall() }
                            },
                            onRestore: {
                                Task {
                                    isRestoring = true
                                    defer { isRestoring = false }
                                    do {
                                        try await purchases.restorePurchases()
                                    } catch {
                                        restoreError = error.localizedDescription
                                    }
                                }
                            }
                        )
                    }

                    // ── Webhooks ──────────────────────────────────────────
                    SettingsCard {
                        NavigationLink(destination: WebhooksDetailView()) {
                            SettingsItem(
                                icon: "bolt.fill", iconBg: Color(red: 0.18, green: 0.45, blue: 0.95),
                                title: "Webhooks"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Docs / Guides / Send Test ─────────────────────────
                    SettingsCard {
                        Button { safariURL = URL(string: Config.docsURL) } label: {
                            SettingsItem(
                                icon: "doc.fill", iconBg: .orange,
                                title: "Documentation"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Color.appTan)

                        Button { safariURL = URL(string: Config.guidesURL) } label: {
                            SettingsItem(
                                icon: "graduationcap.fill", iconBg: Color(red: 0.22, green: 0.70, blue: 0.35),
                                title: "Guides"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Color.appTan)

                        Button { showTest = true } label: {
                            SettingsItem(
                                icon: "paperplane.fill", iconBg: Color(red: 0.15, green: 0.70, blue: 0.75),
                                title: "Send Test Notification",
                                accessory: .none
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Notification Settings ─────────────────────────────
                    SettingsCard {
                        Button {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        } label: {
                            SettingsItem(
                                icon: "bell.badge.fill", iconBg: Color(red: 0.90, green: 0.25, blue: 0.22),
                                title: "Notification Settings",
                                accessory: .externalLink
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // ── Feedback ──────────────────────────────────────────
                    SettingsCard {
                        Button { requestReview() } label: {
                            SettingsItem(
                                icon: "star.fill", iconBg: Color(red: 1.0, green: 0.76, blue: 0.0),
                                title: "Rate Notifikations",
                                subtitle: "Love the app? Leave a review!",
                                accessory: .none
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(Color.appTan)

                        Link(destination: URL(string: "mailto:hello@notifikations.com?subject=Notifikations%20Feedback")!) {
                            SettingsItem(
                                icon: "envelope.fill", iconBg: Color(red: 0.22, green: 0.60, blue: 0.95),
                                title: "Send Feedback",
                                subtitle: "Report bugs or suggest features",
                                accessory: .externalLink
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // ── About ─────────────────────────────────────────────
                    SettingsCard {
                        NavigationLink(destination: AboutView()) {
                            SettingsItem(
                                icon: "info.circle.fill", iconBg: Color(UIColor.systemGray),
                                title: "About"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(icon: "xmark") { dismiss() }
            }
        }
        .sheet(isPresented: $showTest) { TestNotificationSheet() }
        .sheet(item: $safariURL) { url in
            SafariView(url: url).ignoresSafeArea()
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
        .sheet(isPresented: $showCustomerCenter) {
            CustomerCenterView()
        }
        .alert("Restore Failed", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .alert("Subscription Unavailable", isPresented: Binding(
            get: { paywallError != nil },
            set: { if !$0 { paywallError = nil } }
        )) {
            Button("OK", role: .cancel) { paywallError = nil }
        } message: {
            Text(paywallError ?? "")
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
}

// MARK: - Pro upgrade banner (shown when not subscribed)

private struct ProUpgradeCard: View {
    let isRestoring: Bool
    let onUpgrade: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.appSage)
                        .frame(width: 38, height: 38)
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifikations Pro")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.appDark)
                    Text("Unlock unlimited webhooks & more")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appDark.opacity(0.5))
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onUpgrade) {
                    Text("Upgrade")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appCream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.appSage, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(action: onRestore) {
                    Group {
                        if isRestoring {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Restore")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.appDark.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.appDark.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .glassCard(cornerRadius: 20, fallbackOpacity: 0.55)
    }
}

// MARK: - Pro active card (shown when subscribed)

private struct ProActiveCard: View {
    let onManage: () -> Void

    var body: some View {
        Button(action: onManage) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.appSage)
                        .frame(width: 38, height: 38)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifikations Pro")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.appDark)
                    Text("Manage subscription")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appDark.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appDark.opacity(0.3))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .glassCard(cornerRadius: 20, fallbackOpacity: 0.55)
    }
}

// MARK: - Settings card container

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .glassCard(cornerRadius: 20, fallbackOpacity: 0.55)
    }
}

// MARK: - Settings item row

enum SettingsAccessory { case chevron, externalLink, none }

struct SettingsItem: View {
    let icon: String
    let iconBg: Color
    let title: String
    var subtitle: String? = nil
    var accessory: SettingsAccessory = .chevron

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconBg)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Color.appDark)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appDark.opacity(0.45))
                }
            }

            Spacer()

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appDark.opacity(0.3))
            case .externalLink:
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appDark.opacity(0.3))
            case .none:
                EmptyView()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }
}

// MARK: - Webhooks detail screen

struct WebhooksDetailView: View {
    @Query(sort: \NotificationRecord.receivedAt, order: .reverse)
    private var records: [NotificationRecord]

    @Environment(\.dismiss) private var dismiss

    @AppStorage("deviceCustomName") private var deviceCustomName = ""

    @State private var showTest             = false
    @State private var shareContent         = ""
    @State private var showShare            = false
    @State private var showRotateAlert      = false
    @State private var isRotating           = false
    @State private var rotateSuccess        = false
    @State private var showDeviceDetails    = false
    @State private var showRenameAlert      = false
    @State private var renameText           = ""
    @State private var showRotateDeviceAlert = false
    @State private var showDeleteAlert      = false
    @State private var isPerformingAction   = false
    @State private var showCreateWebhook    = false
    @State private var deletingWebhookError: String?

    @ObservedObject private var secrets      = SecretManager.shared
    @ObservedObject private var namedHooks   = NamedWebhookManager.shared
    private let baseURL = Config.apiV1

    var userURL:    String { baseURL + secrets.userSecret }
    var deviceURL:  String { baseURL + secrets.deviceSecret }
    var lastUsed:   Date?  { records.first?.receivedAt }
    var displayDeviceName: String {
        if !deviceCustomName.isEmpty { return deviceCustomName }
        #if targetEnvironment(macCatalyst)
        return ProcessInfo.processInfo.hostName
        #else
        return UIDevice.current.name
        #endif
    }

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    privacyWarningSection
                    allDevicesSection
                    singleDeviceSection
                    customWebhooksSection
                    rotateSection
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(icon: "chevron.left") { dismiss() }
            }
        }
        .sheet(isPresented: $showTest)          { TestNotificationSheet() }
        .sheet(isPresented: $showShare)         { ShareSheet(items: [shareContent]) }
        .sheet(isPresented: $showCreateWebhook) { CreateNamedWebhookSheet() }
        .sheet(isPresented: $showDeviceDetails) {
            DeviceDetailSheet(deviceName: displayDeviceName, url: deviceURL, secret: secrets.deviceSecret)
        }
        .alert("Rotate All Secrets?", isPresented: $showRotateAlert) {
            Button("Rotate", role: .destructive) { Task { await rotateAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All webhook URLs will stop working, including custom webhooks. Update any scripts using them.")
        }
        .alert("Rotate Device Secret?", isPresented: $showRotateDeviceAlert) {
            Button("Rotate", role: .destructive) { Task { await rotateDevice() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device's webhook URL will change. Old URL stops working immediately.")
        }
        .alert("Delete Device?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { Task { await deleteDevice() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device will be unregistered and stop receiving notifications.")
        }
        .alert("Rename Device", isPresented: $showRenameAlert) {
            TextField("Device name", text: $renameText)
            Button("Save") { if !renameText.isEmpty { deviceCustomName = renameText } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Done", isPresented: $rotateSuccess) {
            Button("OK") {}
        } message: {
            Text("Webhook secrets have been updated.")
        }
        .alert("Delete Failed", isPresented: Binding(
            get: { deletingWebhookError != nil },
            set: { if !$0 { deletingWebhookError = nil } }
        )) {
            Button("OK", role: .cancel) { deletingWebhookError = nil }
        } message: {
            Text(deletingWebhookError ?? "")
        }
    }

    @ViewBuilder private var privacyWarningSection: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.35, green: 0.30, blue: 0.88))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Keep your webhook URLs private")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appDark)
                Text("Anyone with access can send notifications to your devices.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appDark.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard(cornerRadius: 16, fallbackOpacity: 0.6)
    }

    @ViewBuilder private var allDevicesSection: some View {
        WebhookSectionView(
            title: "Send to All Devices",
            subtitle: Text("Send notifications to ") + Text("all your devices").bold() + Text(" with this webhook."),
            url: userURL,
            secret: secrets.userSecret,
            lastUsed: lastUsed,
            onSendTest: { showTest = true },
            onShare: { content in shareContent = content; showShare = true }
        )
    }

    @ViewBuilder private var singleDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Send to a Single Device")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.appDark)
                (Text("Send notifications to a ") + Text("single device").bold() + Text(" using its webhook."))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appDark.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.appDark.opacity(0.45))
                    .frame(width: 36)
                Text(displayDeviceName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appDark)
                    .lineLimit(1)
                Text("This Device")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appCream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appSage, in: Capsule())
                Spacer()
                Menu {
                    Button { showDeviceDetails = true } label: {
                        Label("Details", systemImage: "info.circle")
                    }
                    Button {
                        renameText = displayDeviceName
                        showRenameAlert = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { showRotateDeviceAlert = true } label: {
                        Label("Rotate Secret", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appDark.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .glassIconButton(cornerRadius: 10)
                }
            }
            .padding(16)
            .glassCard(cornerRadius: 16, fallbackOpacity: 0.55)
        }
    }

    @ViewBuilder private var customWebhooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Webhooks")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.appDark)
                    Text("Create named URLs targeting this device or all your devices.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appDark.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { showCreateWebhook = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appDark.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .glassIconButton(cornerRadius: 10)
                }
                .buttonStyle(.plain)
            }
            if namedHooks.webhooks.isEmpty {
                HStack {
                    Spacer()
                    Text("No custom webhooks yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appDark.opacity(0.35))
                    Spacer()
                }
                .padding(.vertical, 20)
                .glassCard(cornerRadius: 16, fallbackOpacity: 0.4)
            } else {
                ForEach(namedHooks.webhooks) { webhook in
                    NamedWebhookRow(webhook: webhook) {
                        Task {
                            do {
                                try await namedHooks.delete(webhook)
                            } catch {
                                deletingWebhookError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            if let err = deletingWebhookError {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.horizontal, 4)
            }
            Text("Secrets are stored on this device only and are not synced to other devices.")
                .font(.caption)
                .foregroundStyle(Color.appDark.opacity(0.4))
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder private var rotateSection: some View {
        Button { showRotateAlert = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(isRotating ? "Rotating…" : "Rotate All Secrets")
                    .fontWeight(.medium)
                if isRotating { Spacer(); ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .glassCard(cornerRadius: 16, fallbackOpacity: 0.55)
            .foregroundStyle(Color.red.opacity(0.8))
        }
        .disabled(isRotating)
        Text("Rotating generates new URLs and deletes all custom webhooks. Old URLs stop working immediately.")
            .font(.caption)
            .foregroundStyle(Color.appDark.opacity(0.4))
            .padding(.horizontal, 4)
    }

    private func rotateAll() async {
        isRotating = true
        defer { isRotating = false }
        guard let token = UserDefaults.standard.string(forKey: "apnsDeviceToken") else { return }
        do {
            let oldDeviceSecret = secrets.deviceSecret
            let oldUserSecret = secrets.userSecret
            _ = try await APIService.shared.rotateUserSecret(
                deviceToken: token,
                deviceSecret: oldDeviceSecret,
                oldUserSecret: oldUserSecret
            )
            _ = try await APIService.shared.rotateDeviceSecret(
                deviceToken: token,
                oldSecret: oldDeviceSecret
            )
            // Delete all named webhooks — ownerDigest was re-keyed by the rotate above,
            // so the new deviceDigest (now in SecretManager) is authoritative for deletion.
            for webhook in namedHooks.webhooks {
                try? await namedHooks.delete(webhook)
            }
            rotateSuccess = true
        } catch {}
    }

    private func rotateDevice() async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        guard let token = UserDefaults.standard.string(forKey: "apnsDeviceToken") else { return }
        do {
            _ = try await APIService.shared.rotateDeviceSecret(
                deviceToken: token, oldSecret: secrets.deviceSecret)
            rotateSuccess = true
        } catch {}
    }

    private func deleteDevice() async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        guard let token = UserDefaults.standard.string(forKey: "apnsDeviceToken") else { return }
        do {
            try await APIService.shared.unregister(secret: secrets.deviceSecret, deviceToken: token)
        } catch {}
    }
}

// MARK: - Device Detail Sheet

struct DeviceDetailSheet: View {
    let deviceName: String
    let url: String
    let secret: String

    @State private var shareContent = ""
    @State private var showShare    = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appCream.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        WebhookSectionView(
                            title: deviceName,
                            subtitle: Text("Sends notifications only to ") + Text("this device").bold() + Text("."),
                            url: url,
                            secret: secret,
                            lastUsed: nil,
                            onSendTest: {},
                            onShare: { content in shareContent = content; showShare = true }
                        )
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(deviceName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CircleIconButton(icon: "xmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) { ShareSheet(items: [shareContent]) }
        }
    }
}

// MARK: - About screen

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    SettingsCard {
                        AboutRow(label: "Version",
                                 value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        Divider().overlay(Color.appTan)
                        AboutRow(label: "Build",
                                 value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                    }

                    SettingsCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Device Token")
                                .font(.system(size: 17))
                                .foregroundStyle(Color.appDark)
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                            Text(UserDefaults.standard.string(forKey: "apnsDeviceToken") ?? "Not registered")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.appDark.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
                        }
                    }

                    SettingsCard {
                        HStack(spacing: 0) {
                            Text("Made with ❤️ by ")
                                .foregroundStyle(Color.appDark.opacity(0.8))
                            Link("Idan Buzaglo", destination: URL(string: "https://buzagloidan.com")!)
                                .foregroundStyle(Color.appSage)
                        }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 10)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(icon: "chevron.left") { dismiss() }
            }
        }
    }
}

struct AboutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(Color.appDark)
            Spacer()
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(Color.appDark.opacity(0.5))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }
}
