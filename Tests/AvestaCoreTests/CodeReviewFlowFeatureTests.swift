import ComposableArchitecture
import XCTest
@testable import AvestaCore

@MainActor
final class CodeReviewFlowFeatureTests: XCTestCase {
    func testCommentBoardAndTerminalPasteFlow() async {
        let file = Self.file
        let now = Date(timeIntervalSince1970: 1_782_835_200)
        let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let boardItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let store = TestStore(
            initialState: CodeReviewFlowFeature.State(
                session: CodeReviewFlowFeature.CodeReviewSessionState(
                    diffSpec: "origin/main...HEAD",
                    repoPath: URL(fileURLWithPath: "/tmp/repo"),
                    files: [file]
                )
            )
        ) {
            CodeReviewFlowFeature()
        }

        await store.send(.nextChangeButtonTapped) {
            $0.navigation.focusedChangeIndex = 1
        }

        await store.send(.previousChangeButtonTapped) {
            $0.navigation.focusedChangeIndex = 0
        }

        let pendingLine = CodeReviewFlowFeature.PendingLine(
            fileID: file.id,
            lineNumber: 2,
            content: "let title = \"New\""
        )
        await store.send(.selectLine(pendingLine)) {
            $0.selectedLine = pendingLine
        }

        await store.send(.commentTextChanged("Prefer a localized title here.")) {
            $0.commentText = "Prefer a localized title here."
        }

        await store.send(.saveCommentButtonTapped(id: commentID, createdAt: now)) {
            $0.session.comments = [
                ReviewComment(
                    id: commentID,
                    fileID: file.id,
                    startLine: 2,
                    endLine: 2,
                    highlightedText: "let title = \"New\"",
                    text: "Prefer a localized title here.",
                    createdAt: now
                )
            ]
            $0.selectedLine = nil
            $0.commentText = ""
        }

        await store.send(.sendReviewToBoardButtonTapped(id: boardItemID, now: now)) {
            $0.boardItems = [
                BoardItem(
                    id: boardItemID,
                    content: """
                    # Code Review: origin/main...HEAD @ 2026-06-30T16:00:00Z

                    ## `Sources/App.swift`

                    ### Line 2
                    ```swift
                    let title = "New"
                    ```
                    Prefer a localized title here.
                    """,
                    source: "Code Review: origin/main...HEAD",
                    createdAt: now
                )
            ]
        }

        await store.send(.switchToTerminal) {
            $0.activeTab = .terminal
        }
        await store.send(.pasteBoardItemToTerminal(boardItemID)) {
            $0.terminalPendingPaste = $0.boardItems[0].content
        }
    }

    func testScopeSwitchPreservesSelectedFileWhenPossible() async {
        let gitFile = Self.file
        let lastTurnFile = FileDiff(
            id: gitFile.id,
            path: gitFile.path,
            status: .modified,
            hunks: [
                DiffHunk(
                    oldStart: 6,
                    oldCount: 2,
                    newStart: 6,
                    newCount: 3,
                    lines: [
                        DiffLine(kind: .context, oldLineNumber: 6, newLineNumber: 6, content: "    var body: some View {"),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 7, content: "        Text(subtitle)")
                    ]
                )
            ]
        )
        let otherFile = FileDiff(path: "Sources/Other.swift", status: .modified, hunks: [])
        let store = TestStore(
            initialState: CodeReviewFlowFeature.State(
                session: CodeReviewFlowFeature.CodeReviewSessionState(
                    diffSpec: "Working tree",
                    repoPath: URL(fileURLWithPath: "/tmp/repo"),
                    files: [otherFile, gitFile],
                    lastTurnFiles: [lastTurnFile],
                    activeFileIndex: 1
                )
            )
        ) {
            CodeReviewFlowFeature()
        }

        await store.send(.scopeSelected(.lastTurnChanges)) {
            $0.session.scope = .lastTurnChanges
            $0.session.activeFileIndex = 0
            $0.navigation = CodeReviewNavigationState(changes: CodeReviewChangeNavigation.changes(in: lastTurnFile))
        }
    }

    func testSendReviewToBoardExportsAllCommentsAsOneItem() async {
        let file = Self.file
        let now = Date(timeIntervalSince1970: 1_782_835_200)
        let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let secondCommentID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        let boardItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let store = TestStore(
            initialState: CodeReviewFlowFeature.State(
                session: CodeReviewFlowFeature.CodeReviewSessionState(
                    diffSpec: "Working tree",
                    repoPath: URL(fileURLWithPath: "/tmp/repo"),
                    files: [file],
                    comments: [
                        ReviewComment(
                            id: commentID,
                            fileID: file.id,
                            startLine: 2,
                            endLine: 2,
                            highlightedText: "let title = \"New\"",
                            text: "Keep this scoped to the review flow.",
                            createdAt: now
                        ),
                        ReviewComment(
                            id: secondCommentID,
                            fileID: file.id,
                            startLine: 3,
                            endLine: 3,
                            highlightedText: "let subtitle = \"Workbench\"",
                            text: "Send all comments together.",
                            createdAt: now
                        )
                    ]
                )
            )
        ) {
            CodeReviewFlowFeature()
        }

        await store.send(.sendReviewToBoardButtonTapped(id: boardItemID, now: now)) {
            $0.boardItems = [
                BoardItem(
                    id: boardItemID,
                    content: """
                    # Code Review: Working tree @ 2026-06-30T16:00:00Z

                    ## `Sources/App.swift`

                    ### Line 2
                    ```swift
                    let title = "New"
                    ```
                    Keep this scoped to the review flow.

                    ### Line 3
                    ```swift
                    let subtitle = "Workbench"
                    ```
                    Send all comments together.
                    """,
                    source: "Code Review: Working tree",
                    createdAt: now
                )
            ]
        }
    }

    private static let file = FileDiff(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        path: "Sources/App.swift",
        status: .modified,
        hunks: [
            DiffHunk(
                oldStart: 1,
                oldCount: 7,
                newStart: 1,
                newCount: 9,
                lines: [
                    DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "import SwiftUI"),
                    DiffLine(kind: .removed, oldLineNumber: 2, newLineNumber: nil, content: "let title = \"Old\""),
                    DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 2, content: "let title = \"New\""),
                    DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 3, content: "let subtitle = \"Workbench\""),
                    DiffLine(kind: .context, oldLineNumber: 3, newLineNumber: 4, content: ""),
                    DiffLine(kind: .context, oldLineNumber: 4, newLineNumber: 5, content: "struct AppView: View {"),
                    DiffLine(kind: .context, oldLineNumber: 5, newLineNumber: 6, content: "    var body: some View {"),
                    DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 7, content: "        Text(subtitle)"),
                    DiffLine(kind: .context, oldLineNumber: 6, newLineNumber: 8, content: "        Text(title)"),
                    DiffLine(kind: .context, oldLineNumber: 7, newLineNumber: 9, content: "    }"),
                    DiffLine(kind: .context, oldLineNumber: 8, newLineNumber: 10, content: "}")
                ]
            )
        ]
    )
}
