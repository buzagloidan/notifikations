import UserNotifications

/// Notification Service Extension — downloads image_url and attaches it to the notification.
/// Add this as a new target in Xcode: File > New > Target > Notification Service Extension
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard
            let content = bestAttemptContent,
            let imageURLString = request.content.userInfo["image_url"] as? String,
            let imageURL = URL(string: imageURLString)
        else {
            deliver()
            return
        }

        downloadAttachment(from: imageURL) { attachment in
            if let attachment {
                content.attachments = [attachment]
            }
            self.deliver()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        deliver()
    }

    private func deliver() {
        guard let handler = contentHandler, let content = bestAttemptContent else { return }
        handler(content)
    }

    private func downloadAttachment(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        URLSession.shared.downloadTask(with: url) { localURL, _, _ in
            guard let localURL else {
                completion(nil)
                return
            }

            // Move to a temp file with the right extension
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let tempURL = localURL.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.moveItem(at: localURL, to: tempURL)

            let attachment = try? UNNotificationAttachment(identifier: "image", url: tempURL)
            completion(attachment)
        }.resume()
    }
}
