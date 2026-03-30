import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \NotificationRecord.receivedAt, order: .reverse)
    private var records: [NotificationRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @State private var selectedRecord: NotificationRecord?
    @State private var showClearConfirm = false

    @AppStorage("notifHistoryEnabled") private var historyEnabled = true
    @AppStorage("notifRetentionDays")  private var retentionDays  = 30

    // MARK: - Helpers

    var retentionLabel: String {
        switch retentionDays {
        case 7:   return "7 days"
        case 14:  return "14 days"
        case 30:  return "1 month"
        case 180: return "6 months"
        case 365: return "1 year"
        default:  return "\(retentionDays) days"
        }
    }

    var groupedRecords: [(date: Date, records: [NotificationRecord])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: records) { cal.startOfDay(for: $0.receivedAt) }
        return dict.keys.sorted(by: >).map { date in
            (date: date, records: dict[date]!.sorted { $0.receivedAt > $1.receivedAt })
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appCream.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Custom header ────────────────────────────────────────────
                HStack {
                    CircleIconButton(icon: "xmark") { dismiss() }

                    Spacer()

                    Text("Recent Notifikations")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.appDark)

                    Spacer()

                    CircleIconButton(icon: "trash") { showClearConfirm = true }
                        .disabled(records.isEmpty)
                        .opacity(records.isEmpty ? 0.3 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── Scrollable content ───────────────────────────────────────
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Inline settings ──────────────────────────────────
                        VStack(spacing: 0) {
                            // Save toggle
                            HStack(spacing: 12) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.appDark.opacity(0.7))
                                    .frame(width: 24)
                                Text("Save Notifikations")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.appDark)
                                Spacer()
                                Toggle("", isOn: $historyEnabled)
                                    .labelsHidden()
                                    .tint(Color.appSage)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider()
                                .overlay(Color.appDark.opacity(0.08))
                                .padding(.leading, 52)

                            // Keep duration
                            Menu {
                                Picker(selection: $retentionDays, label: EmptyView()) {
                                    ForEach(retentionOptions, id: \.days) { option in
                                        Text(option.label).tag(option.days)
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.appDark.opacity(0.7))
                                        .frame(width: 24)
                                    Text("Keep Notifikations")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.appDark)
                                    Spacer()
                                    Text(retentionLabel)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.appDark.opacity(0.45))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.appDark.opacity(0.3))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .disabled(!historyEnabled)
                            .opacity(historyEnabled ? 1 : 0.4)
                            .animation(.default, value: historyEnabled)
                        }
                        .glassCard(cornerRadius: 16)

                        // Empty state
                        if records.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "bell.slash")
                                    .font(.system(size: 44))
                                    .foregroundStyle(Color.appTan)
                                Text("No Notifikations Yet")
                                    .font(.headline)
                                    .foregroundStyle(Color.appDark.opacity(0.5))
                                Text("Notifikations you receive will appear here.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appDark.opacity(0.35))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            // Day-grouped records
                            ForEach(groupedRecords, id: \.date) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Date header
                                    Text(group.date.formatted(.dateTime
                                        .weekday(.wide).day().month(.abbreviated).year()))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.appDark.opacity(0.65))

                                    // Notification card
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.records.enumerated()), id: \.element.id) { idx, record in
                                            if idx > 0 {
                                                Divider()
                                                    .overlay(Color.appDark.opacity(0.08))
                                                    .padding(.leading, 16)
                                            }
                                            Button { selectedRecord = record } label: {
                                                HStack(spacing: 12) {
                                                    Text(record.message)
                                                        .font(.system(size: 16))
                                                        .foregroundStyle(Color.appDark)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    Text(record.receivedAt, format: .dateTime
                                                        .hour(.twoDigits(amPM: .omitted)).minute())
                                                        .font(.system(size: 14, design: .monospaced))
                                                        .foregroundStyle(Color.appDark.opacity(0.4))
                                                        .monospacedDigit()
                                                }
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 13)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .glassCard(cornerRadius: 16, fallbackOpacity: 0.6)
                                }
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
        }
        .confirmationDialog(
            "Clear All Notifikations",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                withAnimation {
                    records.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(records.count) saved notifikations.")
        }
        .sheet(item: $selectedRecord) { record in
            NotificationDetailSheet(record: record)
        }
        .onAppear { purgeExpiredRecords() }
    }

    private func purgeExpiredRecords() {
        guard historyEnabled else { return }
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let expired = records.filter { $0.receivedAt < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }
}

// MARK: - Circle icon button (shared header control)

struct CircleIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appDark)
                .frame(width: 40, height: 40)
                .glassCircleButton()
        }
        .buttonStyle(.plain)
    }
}

private let retentionOptions: [(label: String, days: Int)] = [
    ("7 days",   7),
    ("14 days",  14),
    ("1 month",  30),
    ("6 months", 180),
    ("1 year",   365),
]
