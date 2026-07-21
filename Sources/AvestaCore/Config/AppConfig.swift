import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var workspacesRoot: URL
    public var cacheRoot: URL
    public var databaseURL: URL
    public var notificationPatterns: [String]

    public init(
        workspacesRoot: URL,
        cacheRoot: URL,
        databaseURL: URL,
        notificationPatterns: [String]
    ) {
        self.workspacesRoot = workspacesRoot
        self.cacheRoot = cacheRoot
        self.databaseURL = databaseURL
        self.notificationPatterns = notificationPatterns
    }

    public static var `default`: AppConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationSupport = home
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "AvestaCode", directoryHint: .isDirectory)
        return AppConfig(
            workspacesRoot: home.appending(path: "workspaces", directoryHint: .isDirectory),
            cacheRoot: home
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Caches", directoryHint: .isDirectory)
                .appending(path: "AvestaCode", directoryHint: .isDirectory)
                .appending(path: "repositories", directoryHint: .isDirectory),
            databaseURL: applicationSupport.appending(path: "AvestaCode.sqlite3", directoryHint: .notDirectory),
            notificationPatterns: [
                #"(?i)(?:completed|finished|done)\b"#,
                #"(?i)(?:error|failed|exception)\b"#,
                #"(?i)(?:\?|input required|waiting for)"#
            ]
        )
    }
}
