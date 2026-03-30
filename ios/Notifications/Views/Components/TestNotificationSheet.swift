import SwiftUI

struct TestNotificationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var message = "Hello! 👋"
    @State private var sound = "default"
    @State private var target = WebhookTarget.device
    @State private var isSending = false
    @State private var errorMessage: String?

    private let secrets = SecretManager.shared
    private let baseURL = Config.apiV1

    let sounds = ["default", "brrr", "bell_ringing", "bubble_ding", "cha_ching",
                  "cat_meow", "dog_barking", "door_bell", "duck_quack", "upbeat_bells"]

    enum WebhookTarget: String, CaseIterable {
        case device = "This Device"
        case all = "All Devices"
    }

    var secret: String {
        target == .device ? secrets.deviceSecret : secrets.userSecret
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Picker("Send to", selection: $target) {
                        ForEach(WebhookTarget.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Content") {
                    TextField("Title (optional)", text: $title)
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Sound") {
                    Picker("Sound", selection: $sound) {
                        ForEach(sounds, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Test Notification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }
                        .disabled(message.isEmpty || isSending)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        var payload: [String: String] = ["message": message]
        if !title.isEmpty { payload["title"] = title }
        if sound != "default" { payload["sound"] = sound }

        do {
            var request = URLRequest(url: URL(string: baseURL + secret)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                dismiss()
            } else {
                errorMessage = Self.parseServerError(from: data, response: response)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func parseServerError(from data: Data, response: URLResponse) -> String {
        guard let http = response as? HTTPURLResponse else {
            return "Invalid server response."
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let error = object["error"] as? String
            let reason = object["reason"] as? String
            let host = object["host"] as? String
            let statusCode = object["statusCode"] as? Int

            var parts: [String] = []
            if let error, !error.isEmpty { parts.append(error) }
            if let reason, !reason.isEmpty, reason != error { parts.append(reason) }
            if let host, !host.isEmpty { parts.append("host=\(host)") }
            if let statusCode { parts.append("apnsStatus=\(statusCode)") }

            if !parts.isEmpty {
                return "HTTP \(http.statusCode): " + parts.joined(separator: " | ")
            }
        }

        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return "HTTP \(http.statusCode): \(raw)"
        }

        return "HTTP \(http.statusCode): Request failed."
    }
}
