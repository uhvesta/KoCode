import Foundation

public struct AppSessionSnapshot: Codable, Equatable, Sendable {
    public var workspaces: [WorkspaceSnapshot]
    public var activeWorkspaceID: UUID?
    public var cachedRepos: [CachedRepo]
    public var globalBoardItems: [BoardItem]
    public var isBoardVisible: Bool

    public init(
        workspaces: [WorkspaceSnapshot] = [],
        activeWorkspaceID: UUID? = nil,
        cachedRepos: [CachedRepo] = [],
        globalBoardItems: [BoardItem] = [],
        isBoardVisible: Bool = false
    ) {
        self.workspaces = workspaces
        self.activeWorkspaceID = activeWorkspaceID
        self.cachedRepos = cachedRepos
        self.globalBoardItems = globalBoardItems
        self.isBoardVisible = isBoardVisible
    }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var path: URL
    public var repos: [WorktreeRef]
    public var tabs: [TabSnapshot]
    public var activeTabID: UUID?
    public var boardItems: [BoardItem]

    public init(
        id: UUID,
        name: String,
        path: URL,
        repos: [WorktreeRef],
        tabs: [TabSnapshot],
        activeTabID: UUID?,
        boardItems: [BoardItem]
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.repos = repos
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.boardItems = boardItems
    }
}

public enum TabSnapshot: Codable, Equatable, Sendable {
    case terminal(TerminalTabSnapshot)
    case codeReview(CodeReviewTabSnapshot)

    private enum CodingKeys: String, CodingKey {
        case kind
        case terminal
        case codeReview
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(TabKind.self, forKey: .kind)
        switch kind {
        case .terminal:
            self = .terminal(try container.decode(TerminalTabSnapshot.self, forKey: .terminal))
        case .codeReview:
            self = .codeReview(try container.decode(CodeReviewTabSnapshot.self, forKey: .codeReview))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let snapshot):
            try container.encode(TabKind.terminal, forKey: .kind)
            try container.encode(snapshot, forKey: .terminal)
        case .codeReview(let snapshot):
            try container.encode(TabKind.codeReview, forKey: .kind)
            try container.encode(snapshot, forKey: .codeReview)
        }
    }
}

public struct TerminalTabSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var workingDirectory: URL
    public var resume: TerminalResumeSnapshot?
}

public struct TerminalResumeSnapshot: Codable, Equatable, Sendable {
    public var agent: String
    public var sessionID: String
    public var command: String
    public var workingDirectory: URL?

    public init(agent: String, sessionID: String, command: String, workingDirectory: URL?) {
        self.agent = agent
        self.sessionID = sessionID
        self.command = command
        self.workingDirectory = workingDirectory
    }
}

public struct CodeReviewTabSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var session: CodeReviewSessionSnapshot?
}

public struct CodeReviewSessionSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var diffSpec: String
    public var repoPath: URL
    public var files: [FileDiff]
    public var lastTurnFiles: [FileDiff]
    public var activeFileIndex: Int
    public var comments: [ReviewComment]
    public var scope: CodeReviewScope
    public var diffMode: CodeReviewDiffMode
    public var checkpoint: ReviewCheckpoint?
    public var gitChangesError: String?
    public var lastTurnError: String?

    public init(
        id: UUID,
        diffSpec: String,
        repoPath: URL,
        files: [FileDiff],
        lastTurnFiles: [FileDiff] = [],
        activeFileIndex: Int,
        comments: [ReviewComment],
        scope: CodeReviewScope = .gitChanges,
        diffMode: CodeReviewDiffMode = .file,
        checkpoint: ReviewCheckpoint? = nil,
        gitChangesError: String? = nil,
        lastTurnError: String? = nil
    ) {
        self.id = id
        self.diffSpec = diffSpec
        self.repoPath = repoPath
        self.files = files
        self.lastTurnFiles = lastTurnFiles
        self.activeFileIndex = activeFileIndex
        self.comments = comments
        self.scope = scope
        self.diffMode = diffMode
        self.checkpoint = checkpoint
        self.gitChangesError = gitChangesError
        self.lastTurnError = lastTurnError
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case diffSpec
        case repoPath
        case files
        case lastTurnFiles
        case activeFileIndex
        case comments
        case scope
        case diffMode
        case checkpoint
        case gitChangesError
        case lastTurnError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        diffSpec = try container.decode(String.self, forKey: .diffSpec)
        repoPath = try container.decode(URL.self, forKey: .repoPath)
        files = try container.decode([FileDiff].self, forKey: .files)
        lastTurnFiles = try container.decodeIfPresent([FileDiff].self, forKey: .lastTurnFiles) ?? []
        activeFileIndex = try container.decode(Int.self, forKey: .activeFileIndex)
        comments = try container.decode([ReviewComment].self, forKey: .comments)
        scope = try container.decodeIfPresent(CodeReviewScope.self, forKey: .scope) ?? .gitChanges
        diffMode = try container.decodeIfPresent(CodeReviewDiffMode.self, forKey: .diffMode) ?? .file
        checkpoint = try container.decodeIfPresent(ReviewCheckpoint.self, forKey: .checkpoint)
        gitChangesError = try container.decodeIfPresent(String.self, forKey: .gitChangesError)
        lastTurnError = try container.decodeIfPresent(String.self, forKey: .lastTurnError)
    }
}

public struct AppSessionStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppSessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.avestaSession.decode(AppSessionSnapshot.self, from: data)
    }

    public func save(_ snapshot: AppSessionSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.avestaSession.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "AvestaCode", directoryHint: .isDirectory)
            .appending(path: "session.json", directoryHint: .notDirectory)
    }
}

private extension JSONEncoder {
    static var avestaSession: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var avestaSession: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
