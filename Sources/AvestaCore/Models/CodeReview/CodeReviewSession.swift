import Foundation
import Observation

@Observable
@MainActor
public final class CodeReviewSession {
    public let id: UUID
    public var diffSpec: String
    public var repoPath: URL
    public var files: [FileDiff]
    public var activeFileIndex: Int
    public var comments: [ReviewComment]

    public init(
        id: UUID = UUID(),
        diffSpec: String,
        repoPath: URL,
        files: [FileDiff],
        activeFileIndex: Int = 0,
        comments: [ReviewComment] = []
    ) {
        self.id = id
        self.diffSpec = diffSpec
        self.repoPath = repoPath
        self.files = files
        self.activeFileIndex = activeFileIndex
        self.comments = comments
    }

    public var activeFile: FileDiff? {
        guard files.indices.contains(activeFileIndex) else { return nil }
        return files[activeFileIndex]
    }

    public func addComment(
        fileID: UUID,
        line: Int,
        highlightedText: String,
        text: String
    ) {
        comments.append(
            ReviewComment(
                fileID: fileID,
                startLine: line,
                endLine: line,
                highlightedText: highlightedText,
                text: text
            )
        )
    }

    public func toMarkdown(includeSnippets: Bool = true) -> String {
        var output: [String] = [
            "# Code Review: \(diffSpec) @ \(Self.dateFormatter.string(from: Date()))"
        ]

        for file in files {
            let fileComments = comments.filter { $0.fileID == file.id }
            guard !fileComments.isEmpty else { continue }

            output.append("")
            output.append("## `\(file.path)`")

            for comment in fileComments.sorted(by: { $0.startLine < $1.startLine }) {
                output.append("")
                if comment.startLine == comment.endLine {
                    output.append("### Line \(comment.startLine)")
                } else {
                    output.append("### Lines \(comment.startLine)-\(comment.endLine)")
                }

                if includeSnippets, !comment.highlightedText.isEmpty {
                    output.append("```\(languageIdentifier(for: file.path))")
                    output.append(comment.highlightedText)
                    output.append("```")
                }

                output.append(comment.text)
            }
        }

        if comments.isEmpty {
            output.append("")
            output.append("_No review comments._")
        }

        return output.joined(separator: "\n")
    }

    private func languageIdentifier(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": return "swift"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "md": return "markdown"
        default: return ""
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public struct ReviewComment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let fileID: UUID
    public let startLine: Int
    public let endLine: Int
    public let highlightedText: String
    public var text: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fileID: UUID,
        startLine: Int,
        endLine: Int,
        highlightedText: String,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileID = fileID
        self.startLine = startLine
        self.endLine = endLine
        self.highlightedText = highlightedText
        self.text = text
        self.createdAt = createdAt
    }
}
