import SwiftUI

// MARK: - Webhook card (used by WebhooksDetailView in SettingsView)

struct WebhookCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let description: String
    let url: String
    @Binding var copied: String?

    @State private var showShare = false
    var isCopied: Bool { copied == url }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appDark)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(Color.appDark.opacity(0.5))
                }
                Spacer()
            }

            Divider().overlay(Color.appTan)

            HStack(spacing: 8) {
                Text(url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.appDark.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = url
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = url
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copied == url { copied = nil }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(isCopied ? Color.appGreen : Color.appDark.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .glassIconButton()
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.2), value: isCopied)

                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appDark.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .glassIconButton()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20, fallbackOpacity: 0.55)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [url])
        }
    }
}

// MARK: - Webhook section (Send to All Devices card in WebhooksDetailView)

struct WebhookSectionView: View {
    let title: String
    let subtitle: Text
    let url: String
    let secret: String
    let lastUsed: Date?
    let onSendTest: () -> Void
    let onShare: (String) -> Void

    @State private var copied = false

    var curlString: String { "curl -X POST \(url) -d 'Hello world! 👋'" }

    private func doCopy(_ string: String) {
        UIPasteboard.general.string = string
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(duration: 0.25)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }

    private func formatLastUsed(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy 'at' HH:mm"
        return df.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.appDark)
                subtitle
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appDark.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Code card
            CodeCard(url: url, onSendTest: onSendTest)

            // Action buttons
            HStack(spacing: 10) {
                // Copy — menu with URL / Secret / cURL
                Menu {
                    Button { doCopy(url)       } label: { Label("Copy URL",    systemImage: "link") }
                    Button { doCopy(secret)    } label: { Label("Copy Secret", systemImage: "key") }
                    Button { doCopy(curlString)} label: { Label("Copy cURL",   systemImage: "terminal") }
                } label: {
                    HStack(spacing: 8) {
                        Text(copied ? "Copied!" : "Copy").fontWeight(.semibold)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 15))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(copied ? Color.appDark : Color.appSage, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Color.appCream)
                }

                // Share — menu with URL / Secret / cURL
                Menu {
                    Button { onShare(url)       } label: { Label("Share URL",    systemImage: "link") }
                    Button { onShare(secret)    } label: { Label("Share Secret", systemImage: "key") }
                    Button { onShare(curlString)} label: { Label("Share cURL",   systemImage: "terminal") }
                } label: {
                    if #available(iOS 26, macOS 26, *) {
                        HStack(spacing: 8) {
                            Text("Share").fontWeight(.semibold)
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        .foregroundStyle(Color.appDark)
                    } else {
                        HStack(spacing: 8) {
                            Text("Share").fontWeight(.semibold)
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(Color.appDark.opacity(0.2), lineWidth: 1.5))
                        .foregroundStyle(Color.appDark)
                    }
                }
            }

            // Last used timestamp
            if let lastUsed {
                HStack(spacing: 5) {
                    Image(systemName: "link").font(.system(size: 11))
                    Text("Webhook was used \(formatLastUsed(lastUsed)).")
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color.appDark.opacity(0.4))
            }
        }
    }
}

// MARK: - Copied badge

struct CopiedBadge: View {
    var body: some View {
        Label("Copied", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Color.appGreen, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
