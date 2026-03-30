import SwiftUI

// MARK: - History Card

struct HistoryCard: View {
    let record: NotificationRecord
    let isEditing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title ?? "Notification")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(record.title != nil ? Color.appDark : Color.appDark.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    Text(record.receivedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Color.appDark.opacity(0.35))
                }

                Text(record.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.appDark.opacity(0.6))
                    .lineLimit(2)

                if (record.sound != nil && record.sound != "default") || record.openURL != nil {
                    HStack(spacing: 8) {
                        if let sound = record.sound, sound != "default" {
                            Label(sound, systemImage: "speaker.wave.2")
                                .font(.caption2)
                                .foregroundStyle(Color.appDark.opacity(0.35))
                        }
                        if record.openURL != nil {
                            Label("Link", systemImage: "link")
                                .font(.caption2)
                                .foregroundStyle(Color.appDark.opacity(0.35))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 16, fallbackOpacity: 0.6)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { if !isEditing { onTap() } }
        }
        .animation(.spring(duration: 0.3), value: isEditing)
    }
}

// MARK: - Detail Sheet

struct NotificationDetailSheet: View {
    let record: NotificationRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let title = record.title {
                    LabeledContent("Title", value: title)
                }
                if let subtitle = record.subtitle {
                    LabeledContent("Subtitle", value: subtitle)
                }
                LabeledContent("Message") {
                    Text(record.message).multilineTextAlignment(.trailing)
                }
                LabeledContent("Received", value: record.receivedAt.formatted())
                if let sound = record.sound {
                    LabeledContent("Sound", value: sound)
                }
                if let url = record.openURL {
                    LabeledContent("Link") {
                        Link(url, destination: URL(string: url)!)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let imageURL = record.imageURL {
                    LabeledContent("Image URL", value: imageURL)
                }
            }
            .navigationTitle("Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
