import Foundation

public struct AppConfig: Codable, Sendable {
    public var workspacesRoot: URL
    public var cacheRoot: URL
    public var notificationPatterns: [String]

    public init(
        workspacesRoot: URL,
        cacheRoot: URL,
        notificationPatterns: [String]
    ) {
        self.workspacesRoot = workspacesRoot
        self.cacheRoot = cacheRoot
        self.notificationPatterns = notificationPatterns
    }

    public static var `default`: AppConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppConfig(
            workspacesRoot: home.appending(path: "workspaces", directoryHint: .isDirectory),
            cacheRoot: home
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Caches", directoryHint: .isDirectory)
                .appending(path: "avestacode", directoryHint: .isDirectory),
            notificationPatterns: [
                #"(?i)(?:completed|finished|done)\b"#,
                #"(?i)(?:error|failed|exception)\b"#,
                #"(?i)(?:\?|input required|waiting for)"#
            ]
        )
    }
}
