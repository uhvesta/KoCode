import ComposableArchitecture
import XCTest
@testable import AvestaCore

@MainActor
final class AppFeatureTests: XCTestCase {
    func testWorkspaceTabAndBoardFlow() async {
        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let terminalID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let reviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
        let now = Date(timeIntervalSince1970: 1_782_835_200)
        let store = TestStore(
            initialState: AppFeature.State(
                workspaces: [
                    AppFeature.WorkspaceState(
                        id: workspaceID,
                        name: "Fixture",
                        path: URL(fileURLWithPath: "/tmp/fixture"),
                        tabs: [
                            .terminal(AppFeature.TerminalTabState(id: terminalID, workingDirectory: URL(fileURLWithPath: "/tmp/fixture")))
                        ],
                        activeTabID: terminalID
                    )
                ],
                activeWorkspaceID: workspaceID
            )
        ) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.terminalOutput(tabID: terminalID, output: "hello terminal"))
        await store.send(.sendActiveTerminalOutputToBoard(id: boardID, createdAt: now))
        await store.send(.addCodeReviewTab(id: reviewID))
        await store.send(.selectTab(index: 0))
        await store.send(.pasteMostRecentBoardItemToActiveTerminal)
        await store.send(.closeActiveTabOrWorkspace)
        await store.send(.closeActiveTabOrWorkspace)
        await store.send(.closeActiveTabOrWorkspace)

        XCTAssertTrue(store.state.workspaces.isEmpty)
        XCTAssertNil(store.state.activeWorkspaceID)
        XCTAssertNotNil(store.state.lastPersistenceSnapshot)
    }

    func testCodeReviewReducerFeedsWorkspaceBoard() async {
        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let reviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        let fileID = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
        let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-000000000505")!
        let now = Date(timeIntervalSince1970: 1_782_835_200)
        let file = FileDiff(
            id: fileID,
            path: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(oldStart: 1, oldCount: 0, newStart: 1, newCount: 1, lines: [
                    DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 1, content: "let title = \"New\"")
                ])
            ]
        )
        let flow = CodeReviewFlowFeature.State(
            session: CodeReviewFlowFeature.CodeReviewSessionState(
                diffSpec: "origin/main",
                repoPath: URL(fileURLWithPath: "/tmp/repo"),
                files: [file]
            )
        )
        let store = TestStore(
            initialState: AppFeature.State(
                workspaces: [
                    AppFeature.WorkspaceState(
                        id: workspaceID,
                        name: "Review",
                        path: URL(fileURLWithPath: "/tmp/repo"),
                        tabs: [.codeReview(AppFeature.CodeReviewTabState(id: reviewID, flow: flow))],
                        activeTabID: reviewID
                    )
                ],
                activeWorkspaceID: workspaceID
            )
        ) {
            AppFeature()
        }
        store.exhaustivity = .off

        let pendingLine = CodeReviewFlowFeature.PendingLine(
            fileID: fileID,
            lineNumber: 1,
            content: "let title = \"New\""
        )
        await store.send(AppFeature.Action.codeReview(tabID: reviewID, CodeReviewFlowFeature.Action.selectLine(pendingLine))) {
            guard case .codeReview(var tab) = $0.workspaces[0].tabs[0] else { return }
            tab.flow?.selectedLine = pendingLine
            $0.workspaces[0].tabs[0] = .codeReview(tab)
        }
        await store.send(AppFeature.Action.codeReview(tabID: reviewID, CodeReviewFlowFeature.Action.commentTextChanged("Use the product name constant."))) {
            guard case .codeReview(var tab) = $0.workspaces[0].tabs[0] else { return }
            tab.flow?.selectedLine = pendingLine
            tab.flow?.commentText = "Use the product name constant."
            $0.workspaces[0].tabs[0] = .codeReview(tab)
        }
        await store.send(AppFeature.Action.codeReview(tabID: reviewID, CodeReviewFlowFeature.Action.saveCommentButtonTapped(id: commentID, createdAt: now))) {
            guard case .codeReview(var tab) = $0.workspaces[0].tabs[0] else { return }
            tab.flow?.session.comments = [
                ReviewComment(
                    id: commentID,
                    fileID: fileID,
                    startLine: 1,
                    endLine: 1,
                    highlightedText: "let title = \"New\"",
                    text: "Use the product name constant.",
                    createdAt: now
                )
            ]
            tab.flow?.selectedLine = nil
            tab.flow?.commentText = ""
            $0.workspaces[0].tabs[0] = .codeReview(tab)
        }
        await store.send(AppFeature.Action.codeReview(tabID: reviewID, CodeReviewFlowFeature.Action.sendReviewToBoardButtonTapped(id: boardID, now: now))) {
            guard case .codeReview(var tab) = $0.workspaces[0].tabs[0] else { return }
            let item = BoardItem(
                id: boardID,
                content: """
                # Code Review: origin/main @ 2026-06-30T16:00:00Z

                ## `Sources/App.swift`

                ### Line 1
                ```swift
                let title = "New"
                ```
                Use the product name constant.
                """,
                source: "Code Review: origin/main",
                createdAt: now
            )
            tab.flow?.boardItems = [item]
            $0.workspaces[0].tabs[0] = .codeReview(tab)
            $0.workspaces[0].boardItems = [item]
        }
    }
}
