import Foundation

public struct NotificationPattern: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let pattern: String
    public let title: String

    public init(pattern: String, title: String) {
        self.pattern = pattern
        self.title = title
    }

    public static let defaults: [NotificationPattern] = [
        NotificationPattern(pattern: #"(?i)(?:completed|finished|done)\b"#, title: "Command Completed"),
        NotificationPattern(pattern: #"(?i)(?:error|failed|exception)\b"#, title: "Terminal Error"),
        NotificationPattern(pattern: #"(?i)(?:\?|input required|waiting for)"#, title: "Input Required")
    ]
}
