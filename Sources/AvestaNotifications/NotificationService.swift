import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
public final class NotificationService {
    public init() {}

    public func requestPermission() async {
        guard canUseUserNotifications else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func notify(title: String, body: String, tabID: UUID) {
        guard canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
