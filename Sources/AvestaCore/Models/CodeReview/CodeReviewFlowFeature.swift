import ComposableArchitecture
import Foundation

@Reducer
public struct CodeReviewFlowFeature: Sendable {
    public init() {}

    @ObservableState
    public struct State: Equatable, Sendable {
        public var session: CodeReviewSessionState
        public var boardItems: [BoardItem]
        public var activeTab: ActiveTab
        public var terminalPendingPaste: String?
        public var navigation: CodeReviewNavigationState
        public var selectedLine: PendingLine?
        public var commentText: String

        public init(
            session: CodeReviewSessionState,
            boardItems: [BoardItem] = [],
            activeTab: ActiveTab = .codeReview,
            terminalPendingPaste: String? = nil,
            navigation: CodeReviewNavigationState? = nil,
            selectedLine: PendingLine? = nil,
            commentText: String = ""
        ) {
            self.session = session
            self.boardItems = boardItems
            self.activeTab = activeTab
            self.terminalPendingPaste = terminalPendingPaste
            self.navigation = navigation ?? CodeReviewNavigationState(
                changes: session.activeFile.map(CodeReviewChangeNavigation.changes(in:)) ?? []
            )
            self.selectedLine = selectedLine
            self.commentText = commentText
        }
    }

    public enum ActiveTab: Equatable, Sendable {
        case codeReview
        case terminal
    }

    public struct CodeReviewSessionState: Equatable, Sendable {
        public var id: UUID
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

        public func markdown(now: Date = Date()) -> String {
            var output: [String] = [
                "# Code Review: \(diffSpec) @ \(Self.dateFormatter.string(from: now))"
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
                    if !comment.highlightedText.isEmpty {
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

    public struct PendingLine: Equatable, Sendable {
        public var fileID: UUID
        public var lineNumber: Int
        public var content: String

        public init(fileID: UUID, lineNumber: Int, content: String) {
            self.fileID = fileID
            self.lineNumber = lineNumber
            self.content = content
        }
    }

    public enum Action: Equatable, Sendable {
        case previousChangeButtonTapped
        case nextChangeButtonTapped
        case activeFileChanged(Int)
        case selectLine(PendingLine)
        case commentTextChanged(String)
        case saveCommentButtonTapped(id: UUID, createdAt: Date)
        case sendReviewToBoardButtonTapped(id: UUID, now: Date)
        case switchToTerminal
        case pasteBoardItemToTerminal(UUID)
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .previousChangeButtonTapped:
                CodeReviewChangeNavigation.reduce(state: &state.navigation, action: .previousChange)
                return .none

            case .nextChangeButtonTapped:
                CodeReviewChangeNavigation.reduce(state: &state.navigation, action: .nextChange)
                return .none

            case .activeFileChanged(let index):
                guard state.session.files.indices.contains(index) else { return .none }
                state.session.activeFileIndex = index
                state.navigation = CodeReviewNavigationState(
                    changes: CodeReviewChangeNavigation.changes(in: state.session.files[index])
                )
                return .none

            case .selectLine(let line):
                state.selectedLine = line
                state.commentText = state.session.comments.first {
                    $0.fileID == line.fileID && $0.startLine == line.lineNumber
                }?.text ?? ""
                return .none

            case .commentTextChanged(let text):
                state.commentText = text
                return .none

            case .saveCommentButtonTapped(let id, let createdAt):
                guard let selectedLine = state.selectedLine else { return .none }
                let trimmed = state.commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    state.selectedLine = nil
                    state.commentText = ""
                    return .none
                }

                if let index = state.session.comments.firstIndex(where: {
                    $0.fileID == selectedLine.fileID && $0.startLine == selectedLine.lineNumber
                }) {
                    state.session.comments[index].text = trimmed
                } else {
                    state.session.comments.append(
                        ReviewComment(
                            id: id,
                            fileID: selectedLine.fileID,
                            startLine: selectedLine.lineNumber,
                            endLine: selectedLine.lineNumber,
                            highlightedText: selectedLine.content,
                            text: trimmed,
                            createdAt: createdAt
                        )
                    )
                }
                state.selectedLine = nil
                state.commentText = ""
                return .none

            case .sendReviewToBoardButtonTapped(let id, let now):
                let content = state.session.markdown(now: now).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return .none }
                state.boardItems.insert(
                    BoardItem(
                        id: id,
                        content: content,
                        source: "Code Review: \(state.session.diffSpec)",
                        createdAt: now
                    ),
                    at: 0
                )
                return .none

            case .switchToTerminal:
                state.activeTab = .terminal
                return .none

            case .pasteBoardItemToTerminal(let id):
                guard let item = state.boardItems.first(where: { $0.id == id }) else { return .none }
                state.terminalPendingPaste = item.content
                return .none
            }
        }
    }
}
