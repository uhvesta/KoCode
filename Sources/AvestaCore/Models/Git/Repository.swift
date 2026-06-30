import Foundation

public struct WorktreeRef: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let repoName: String
    public let bareRepoPath: URL
    public let worktreePath: URL
    public let branch: String
    public let remoteURL: String

    public init(
        id: UUID = UUID(),
        repoName: String,
        bareRepoPath: URL,
        worktreePath: URL,
        branch: String,
        remoteURL: String
    ) {
        self.id = id
        self.repoName = repoName
        self.bareRepoPath = bareRepoPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.remoteURL = remoteURL
    }
}

public struct CachedRepo: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let bareClonePath: URL
    public let remoteURL: String
    public var lastFetched: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        bareClonePath: URL,
        remoteURL: String,
        lastFetched: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.bareClonePath = bareClonePath
        self.remoteURL = remoteURL
        self.lastFetched = lastFetched
    }
}
