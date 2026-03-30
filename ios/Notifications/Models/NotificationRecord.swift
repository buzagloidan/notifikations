import SwiftData
import Foundation

@Model
final class NotificationRecord {
    var id: UUID
    var title: String?
    var subtitle: String?
    var message: String
    var sound: String?
    var openURL: String?
    var imageURL: String?
    var receivedAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        subtitle: String? = nil,
        message: String,
        sound: String? = nil,
        openURL: String? = nil,
        imageURL: String? = nil,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.sound = sound
        self.openURL = openURL
        self.imageURL = imageURL
        self.receivedAt = receivedAt
    }

    static func from(userInfo: [AnyHashable: Any]) -> NotificationRecord? {
        guard let aps = userInfo["aps"] as? [String: Any],
              let alert = aps["alert"] as? [String: Any],
              let body = alert["body"] as? String else { return nil }

        return NotificationRecord(
            title: alert["title"] as? String,
            subtitle: alert["subtitle"] as? String,
            message: body,
            sound: aps["sound"] as? String,
            openURL: userInfo["open_url"] as? String,
            imageURL: userInfo["image_url"] as? String
        )
    }
}
