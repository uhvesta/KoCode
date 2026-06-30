import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
public final class NotificationService {
    public var inAppBanners: [NotificationBannerModel] = []

    public init() {}

    public func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func notify(title: String, body: String, tabID: UUID) {
        inAppBanners.insert(NotificationBannerModel(title: title, body: body, tabID: tabID), at: 0)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

public struct NotificationBannerModel: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let tabID: UUID
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, body: String, tabID: UUID, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.tabID = tabID
        self.createdAt = createdAt
    }
}
