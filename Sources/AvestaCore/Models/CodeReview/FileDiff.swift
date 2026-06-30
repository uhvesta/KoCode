import Foundation

public struct FileDiff: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let path: String
    public let oldPath: String?
    public let status: FileStatus
    public let hunks: [DiffHunk]

    public init(
        id: UUID = UUID(),
        path: String,
        oldPath: String? = nil,
        status: FileStatus,
        hunks: [DiffHunk]
    ) {
        self.id = id
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.hunks = hunks
    }
}

public struct DiffHunk: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(
        id: UUID = UUID(),
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [DiffLine]
    ) {
        self.id = id
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct DiffLine: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: DiffLineKind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let content: String

    public init(
        id: UUID = UUID(),
        kind: DiffLineKind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        content: String
    ) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
    }
}

public enum DiffLineKind: String, Hashable, Sendable {
    case context
    case added
    case removed
}

public enum FileStatus: String, Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed
}
