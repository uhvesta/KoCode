import Foundation

public struct AssistantQuestion: Sendable {
    public var repositoryName: String
    public var repositoryPath: URL
    public var filePath: String
    public var side: DiffSide
    public var startLine: Int
    public var endLine: Int
    public var selectedCode: String
    public var surroundingContext: String
    public var question: String

    public init(repositoryName: String, repositoryPath: URL, filePath: String, side: DiffSide, startLine: Int, endLine: Int, selectedCode: String, surroundingContext: String, question: String) {
        self.repositoryName = repositoryName
        self.repositoryPath = repositoryPath
        self.filePath = filePath
        self.side = side
        self.startLine = startLine
        self.endLine = endLine
        self.selectedCode = selectedCode
        self.surroundingContext = surroundingContext
        self.question = question
    }
}

public struct AssistantExecutionPolicy: Sendable, Equatable {
    public var allowsFileEdits: Bool
    public var allowsMutatingTools: Bool

    public static let reviewReadOnly = AssistantExecutionPolicy(allowsFileEdits: false, allowsMutatingTools: false)
}

public struct AssistantStream: Sendable {
    public var providerSessionID: String?
    public var model: String?
    public var chunks: AsyncThrowingStream<String, Error>
}

public protocol AssistantClient: Sendable {
    var provider: AssistantProvider { get }
    func ask(_ question: AssistantQuestion, policy: AssistantExecutionPolicy) async throws -> AssistantStream
    func cancel(sessionID: String?) async
}

public enum AssistantClientError: Error, LocalizedError, Equatable {
    case authentication(String)
    case quota(String)
    case timeout
    case unavailable(String)
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .authentication(let message): return "Authentication required: \(message)"
        case .quota(let message): return "Provider quota exceeded: \(message)"
        case .timeout: return "The assistant request timed out."
        case .unavailable(let message): return "Assistant unavailable: \(message)"
        case .provider(let message): return message
        }
    }

    public var code: String {
        switch self {
        case .authentication: return "authentication"
        case .quota: return "quota"
        case .timeout: return "timeout"
        case .unavailable: return "unavailable"
        case .provider: return "provider"
        }
    }
}

/// The product layer talks only to this SDK-shaped interface. Provider packages register
/// concrete Codex and Copilot clients at application startup; review requests always receive
/// the immutable read-only policy above.
public actor AssistantClientRegistry {
    public static let shared = AssistantClientRegistry()
    private var clients: [AssistantProvider: any AssistantClient] = [:]

    public func register(_ client: any AssistantClient) { clients[client.provider] = client }
    public func client(for provider: AssistantProvider) -> (any AssistantClient)? { clients[provider] }
}

public enum TerminalReviewHandoff {
    public static func format(repository: WorkspaceRepositoryRecord, filePath: String, side: DiffSide, startLine: Int, endLine: Int, excerpt: String, userText: String) -> String {
        """
        Review context (do not modify files unless I ask):
        Repository: \(repository.name) (\(repository.worktreePath.path))
        File: \(filePath)
        Lines: \(side.rawValue) \(startLine)-\(endLine)

        ```
        \(excerpt)
        ```

        \(userText)
        """
    }
}

/// Produces a deterministic, portable review prompt that can either be copied
/// or inserted through a Ghostty surface. It contains only AvestaCode-owned
/// annotation data and never includes terminal output or credentials.
public enum WorkspaceReviewBundleFormatter {
    public static func format(workspace: WorkspaceRecord, annotations: [ReviewAnnotation]) -> String {
        let repositoryOrder = Dictionary(uniqueKeysWithValues: workspace.repositories.enumerated().map { ($0.element.id, $0.offset) })
        let repositoryNames = Dictionary(uniqueKeysWithValues: workspace.repositories.map { ($0.id, $0.name) })
        let sorted = annotations.sorted {
            let left = (repositoryOrder[$0.repositoryID] ?? Int.max, $0.filePath, $0.startLine, $0.createdAt)
            let right = (repositoryOrder[$1.repositoryID] ?? Int.max, $1.filePath, $1.startLine, $1.createdAt)
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            if left.2 != right.2 { return left.2 < right.2 }
            return left.3 < right.3
        }

        var sections = [
            "Workspace review feedback for \"\(workspace.name)\"",
            "",
            "Please address every review item below. Preserve unrelated behavior and report how each item was handled."
        ]
        for (index, annotation) in sorted.enumerated() {
            let repository = repositoryNames[annotation.repositoryID] ?? "Unknown repository"
            let lineLabel = annotation.startLine == annotation.endLine
                ? "line \(annotation.startLine)"
                : "lines \(annotation.startLine)-\(annotation.endLine)"
            let kind = annotation.kind == .comment ? "Comment" : "Question"
            let outdated = annotation.isOutdated ? " [outdated anchor]" : ""
            sections.append("""

            ## \(index + 1). \(repository) — \(annotation.filePath) (\(annotation.side.rawValue) \(lineLabel))\(outdated)

            \(kind):
            \(annotation.userText)

            Selected code:
            \(indented(annotation.selectedCode))
            """)
        }
        return sections.joined(separator: "\n")
    }

    private static func indented(_ value: String) -> String {
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return "    (no source excerpt)" }
        return lines.map { "    \($0)" }.joined(separator: "\n")
    }
}
