import Foundation

public struct FileDiff: Identifiable, Codable, Hashable, Sendable {
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

    public var addedLineCount: Int {
        hunks.flatMap(\.lines).filter { $0.kind == .added }.count
    }

    public var removedLineCount: Int {
        hunks.flatMap(\.lines).filter { $0.kind == .removed }.count
    }

    public var changedNewLineNumbers: Set<Int> {
        Set(hunks.flatMap(\.lines).compactMap { line in
            guard line.kind == .added else { return nil }
            return line.newLineNumber
        })
    }

    public func normalized(oldRoot: String, newRoot: String) -> FileDiff {
        let normalizedPath = Self.normalized(path, removing: newRoot)
        let normalizedOldPath = oldPath.map { Self.normalized($0, removing: oldRoot) }
        return FileDiff(
            id: id,
            path: normalizedPath,
            oldPath: normalizedOldPath == normalizedPath ? nil : normalizedOldPath,
            status: status,
            hunks: hunks
        )
    }

    private static func normalized(_ path: String, removing prefix: String) -> String {
        let candidates = [
            prefix,
            prefix.hasPrefix("/") ? String(prefix.dropFirst()) : prefix
        ]

        for candidate in candidates where !candidate.isEmpty {
            if path == candidate {
                return ""
            }
            if path.hasPrefix(candidate + "/") {
                return String(path.dropFirst(candidate.count + 1))
            }
        }

        return path
    }
}

public struct DiffHunk: Identifiable, Codable, Hashable, Sendable {
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

public struct DiffLine: Identifiable, Codable, Hashable, Sendable {
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

public enum DiffLineKind: String, Codable, Hashable, Sendable {
    case context
    case added
    case removed
}

public enum FileStatus: String, Codable, Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed
}
