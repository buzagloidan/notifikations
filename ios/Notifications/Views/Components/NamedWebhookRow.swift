import SwiftUI

// MARK: - Row card for a single named webhook

struct NamedWebhookRow: View {
    let webhook: NamedWebhook
    let onDelete: () -> Void

    @State private var copied = false
    @State private var shareContent = ""
    @State private var showShare = false
    @State private var showDeleteAlert = false

    private func doCopy(_ string: String) {
        UIPasteboard.general.string = string
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(duration: 0.25)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header: label + scope badge + delete menu
            HStack(spacing: 10) {
                Text(webhook.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appDark)
                    .lineLimit(1)

                ScopeBadge(scope: webhook.scope)

                Spacer()

                Menu {
                    Button { doCopy(webhook.url) } label: {
                        Label("Copy URL", systemImage: "link")
                    }
                    Button { doCopy(webhook.secret) } label: {
                        Label("Copy Secret", systemImage: "key")
                    }
                    Button { doCopy(webhook.curlString) } label: {
                        Label("Copy cURL", systemImage: "terminal")
                    }
                    Divider()
                    Button { shareContent = webhook.url; showShare = true } label: {
                        Label("Share URL", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) { showDeleteAlert = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appDark.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .glassIconButton(cornerRadius: 8)
                }
            }

            // URL row
            HStack(spacing: 8) {
                Text(webhook.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.appDark.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Quick copy button
                Button { doCopy(webhook.url) } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(copied ? Color.appGreen : Color.appDark.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .glassIconButton(cornerRadius: 7)
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.2), value: copied)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, fallbackOpacity: 0.55)
        .sheet(isPresented: $showShare) { ShareSheet(items: [shareContent]) }
        .alert("Delete \"\(webhook.label)\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This webhook URL will stop working immediately.")
        }
    }
}

// MARK: - Scope badge

struct ScopeBadge: View {
    let scope: WebhookScope

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scope.systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(scope.displayName)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.appCream)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.appDark.opacity(0.45), in: Capsule())
    }
}

// MARK: - Create sheet

struct CreateNamedWebhookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = NamedWebhookManager.shared

    @State private var label = ""
    @State private var scope: WebhookScope = .device
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appCream.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Label field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Label")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.appDark.opacity(0.5))
                                .padding(.horizontal, 4)

                            TextField("e.g. CI, Server, Home", text: $label)
                                .font(.system(size: 17))
                                .foregroundStyle(Color.appDark)
                                .padding(14)
                                .glassCard(cornerRadius: 14, fallbackOpacity: 0.55)
                                .autocorrectionDisabled()
                        }

                        // Scope picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Send to")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.appDark.opacity(0.5))
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(WebhookScope.allCases, id: \.self) { option in
                                    Button {
                                        scope = option
                                    } label: {
                                        HStack(spacing: 14) {
                                            Image(systemName: option.systemImage)
                                                .font(.system(size: 15))
                                                .foregroundStyle(Color.appDark.opacity(0.6))
                                                .frame(width: 22)

                                            Text(option.displayName)
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.appDark)

                                            Spacer()

                                            if scope == option {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(Color.appSage)
                                            }
                                        }
                                        .padding(.vertical, 13)
                                        .padding(.horizontal, 14)
                                    }
                                    .buttonStyle(.plain)

                                    if option != WebhookScope.allCases.last {
                                        Divider().overlay(Color.appTan)
                                    }
                                }
                            }
                            .glassCard(cornerRadius: 14, fallbackOpacity: 0.55)
                        }

                        // Error
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.red.opacity(0.8))
                                .padding(.horizontal, 4)
                        }

                        // Create button
                        Button {
                            Task { await create() }
                        } label: {
                            HStack(spacing: 8) {
                                if isCreating {
                                    ProgressView().controlSize(.small).tint(Color.appCream)
                                }
                                Text(isCreating ? "Creating…" : "Create Webhook")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.appCream)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                label.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.appDark.opacity(0.2)
                                    : Color.appSage,
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("New Webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CircleIconButton(icon: "xmark") { dismiss() }
                }
            }
        }
    }

    private func create() async {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            _ = try await manager.create(label: trimmed, scope: scope)
            await MainActor.run { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
