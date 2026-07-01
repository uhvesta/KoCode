import AppKit
import ComposableArchitecture
import SnapshotTesting
import SwiftUI
import XCTest
@testable import AvestaCore
@testable import AvestaUI

@MainActor
final class AppStoreSnapshotTests: XCTestCase {
    func testNoWorkspaceState() {
        assertViewSnapshot(
            MainWindow(store: store(AppFeature.State())),
            named: "no-workspace",
            size: CGSize(width: 900, height: 620)
        )
    }

    func testWorkspaceWithNoTabs() {
        let state = AppFeature.State(
            workspaces: [
                AppFeature.WorkspaceState(
                    id: ids.workspace,
                    name: "Empty Workspace",
                    path: URL(fileURLWithPath: "/tmp/empty-workspace"),
                    tabs: [],
                    activeTabID: nil
                )
            ],
            activeWorkspaceID: ids.workspace
        )
        assertViewSnapshot(
            MainWindow(store: store(state)),
            named: "workspace-no-tabs",
            size: CGSize(width: 900, height: 620)
        )
    }

    func testTerminalTabState() {
        var state = UISnapshotFixtures.appState(ids: ids)
        state.workspaces[0].tabs[0] = .terminal(AppFeature.TerminalTabState(
            id: ids.terminalTab,
            workingDirectory: URL(fileURLWithPath: "/tmp/avestacode-fixture"),
            outputBuffer: "swift test\nBuild complete\n"
        ))
        assertViewSnapshot(
            VStack(spacing: 0) {
                TabBarView(store: store(state), workspace: state.workspaces[0])
                Divider()
                TerminalStateSnapshotView(terminal: state.workspaces[0].activeTerminal!)
            },
            named: "terminal-tab",
            size: CGSize(width: 1000, height: 680)
        )
    }

    func testBoardEmptyAndPopulatedStates() {
        var emptyState = UISnapshotFixtures.appState(ids: ids)
        emptyState.isBoardVisible = true
        assertViewSnapshot(
            BoardPanel(store: store(emptyState), items: []),
            named: "board-empty",
            size: CGSize(width: 360, height: 680)
        )

        var populatedState = emptyState
        populatedState.workspaces[0].boardItems = [
            BoardItem(
                id: ids.boardItem,
                content: "Run the failing test and paste the output.",
                source: "Terminal: Terminal",
                createdAt: fixedDate
            )
        ]
        assertViewSnapshot(
            BoardPanel(store: store(populatedState), items: populatedState.workspaces[0].boardItems),
            named: "board-populated",
            size: CGSize(width: 360, height: 680)
        )
    }

    func testCodeReviewSelectedChunkAndCommentEditor() {
        var state = UISnapshotFixtures.codeReviewAppState(ids: ids)
        if case .codeReview(var tab) = state.workspaces[0].tabs[0] {
            tab.flow?.navigation.focusedChangeIndex = 0
            tab.flow?.selectedLine = CodeReviewFlowFeature.PendingLine(
                fileID: ids.file,
                lineNumber: 2,
                content: "let title = \"New\""
            )
            tab.flow?.commentText = "Prefer a localized title here."
            state.workspaces[0].tabs[0] = .codeReview(tab)
        }
        assertViewSnapshot(
            MainWindow(store: store(state)),
            named: "code-review-selected-chunk-comment-editor",
            size: CGSize(width: 1120, height: 720)
        )
    }

    func testCodeReviewFullFlowScopesInlineCommentAndBoard() async throws {
        let repoURL = try makeCodeReviewRepository()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let file = fullFlowFile
        let lastTurnFile = fullFlowLastTurnFile(fileID: file.id)
        let now = fixedDate
        let checkpoint = ReviewCheckpoint(
            createdAt: now,
            files: [
                ReviewCheckpointFile(path: "Sources/App.swift", content: "import SwiftUI\nlet title = \"New\"\n")
            ]
        )
        let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000002021")!
        let secondCommentID = UUID(uuidString: "00000000-0000-0000-0000-000000002023")!
        let boardItemID = UUID(uuidString: "00000000-0000-0000-0000-000000002022")!

        let flowStore = TestStore(
            initialState: CodeReviewFlowFeature.State(
                session: CodeReviewFlowFeature.CodeReviewSessionState(
                    diffSpec: "Working tree",
                    repoPath: repoURL,
                    files: [file],
                    lastTurnFiles: [lastTurnFile],
                    checkpoint: checkpoint
                )
            )
        ) {
            CodeReviewFlowFeature()
        }

        let pendingLine = CodeReviewFlowFeature.PendingLine(
            fileID: file.id,
            lineNumber: 3,
            content: "let subtitle = \"Workbench\""
        )
        await flowStore.send(.selectLine(pendingLine)) {
            $0.selectedLine = pendingLine
        }
        await flowStore.send(.commentTextChanged("Keep the subtitle behind the review checkpoint context.")) {
            $0.commentText = "Keep the subtitle behind the review checkpoint context."
        }
        await flowStore.send(.saveCommentButtonTapped(id: commentID, createdAt: now)) {
            $0.session.comments = [
                ReviewComment(
                    id: commentID,
                    fileID: file.id,
                    startLine: 3,
                    endLine: 3,
                    highlightedText: "let subtitle = \"Workbench\"",
                    text: "Keep the subtitle behind the review checkpoint context.",
                    createdAt: now
                )
            ]
            $0.selectedLine = nil
            $0.commentText = ""
        }

        let secondPendingLine = CodeReviewFlowFeature.PendingLine(
            fileID: file.id,
            lineNumber: 7,
            content: "        Text(subtitle)"
        )
        await flowStore.send(.selectLine(secondPendingLine)) {
            $0.selectedLine = secondPendingLine
        }
        await flowStore.send(.commentTextChanged("Batch this UI note with the rest of the review comments.")) {
            $0.commentText = "Batch this UI note with the rest of the review comments."
        }
        await flowStore.send(.saveCommentButtonTapped(id: secondCommentID, createdAt: now)) {
            $0.session.comments = [
                ReviewComment(
                    id: commentID,
                    fileID: file.id,
                    startLine: 3,
                    endLine: 3,
                    highlightedText: "let subtitle = \"Workbench\"",
                    text: "Keep the subtitle behind the review checkpoint context.",
                    createdAt: now
                ),
                ReviewComment(
                    id: secondCommentID,
                    fileID: file.id,
                    startLine: 7,
                    endLine: 7,
                    highlightedText: "        Text(subtitle)",
                    text: "Batch this UI note with the rest of the review comments.",
                    createdAt: now
                )
            ]
            $0.selectedLine = nil
            $0.commentText = ""
        }
        await flowStore.send(.sendReviewToBoardButtonTapped(id: boardItemID, now: now)) {
            $0.boardItems = [
                BoardItem(
                    id: boardItemID,
                    content: """
                    # Code Review: Working tree @ 2026-06-30T16:00:00Z

                    ## `Sources/App.swift`

                    ### Line 3
                    ```swift
                    let subtitle = "Workbench"
                    ```
                    Keep the subtitle behind the review checkpoint context.

                    ### Line 7
                    ```swift
                            Text(subtitle)
                    ```
                    Batch this UI note with the rest of the review comments.
                    """,
                    source: "Code Review: Working tree",
                    createdAt: now
                )
            ]
        }

        var state = fullFlowAppState(repoURL: repoURL, flow: flowStore.state)
        assertViewSnapshot(
            reviewFlowSnapshotView(state),
            named: "code-review-full-flow-git-scope",
            size: CGSize(width: 1440, height: 760)
        )

        if case .codeReview(var tab) = state.workspaces[0].tabs[1],
           var flow = tab.flow {
            flow.session.scope = .lastTurnChanges
            flow.session.diffMode = .unified
            flow.session.activeFileIndex = 0
            flow.syncNavigationToActiveFile()
            tab.flow = flow
            state.workspaces[0].tabs[1] = .codeReview(tab)
        }
        assertViewSnapshot(
            reviewFlowSnapshotView(state),
            named: "code-review-full-flow-last-turn-unified",
            size: CGSize(width: 1440, height: 760)
        )
    }

    func testMainWindowWithSidebarTabsCodeReviewBoardAndBanner() {
        var state = UISnapshotFixtures.codeReviewAppState(ids: ids)
        state.isBoardVisible = true
        state.workspaces[0].boardItems = [
            BoardItem(
                id: ids.boardItem,
                content: "Review comment ready to paste.",
                source: "Code Review: origin/main...HEAD",
                createdAt: fixedDate
            )
        ]
        state.notificationBadges[ids.reviewTab] = 2
        state.notificationBanners = [
            InAppNotificationBanner(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001009")!,
                title: "Terminal Needs Attention",
                body: "Build failed on line 42",
                tabID: ids.reviewTab,
                createdAt: fixedDate
            )
        ]
        assertViewSnapshot(
            MainWindow(store: store(state)),
            named: "main-window-code-review-board-banner",
            size: CGSize(width: 1180, height: 720)
        )
    }

    func testAddRepositorySheet() {
        var state = UISnapshotFixtures.appState(ids: ids)
        state.cachedRepos = [cachedRepo]
        state.addRepositoryForm.remoteURL = "https://example.com/new-repo.git"
        assertViewSnapshot(
            AddRepositorySheet(store: store(state)),
            named: "add-repository-sheet",
            size: CGSize(width: 520, height: 360)
        )
    }

    func testNewWorkspaceSheet() {
        var state = UISnapshotFixtures.appState(ids: ids)
        state.cachedRepos = [cachedRepo]
        state.newWorkspaceForm.name = "New Workspace"
        state.newWorkspaceForm.remoteURL = "https://example.com/project.git"
        assertViewSnapshot(
            NewWorkspaceSheet(store: store(state)),
            named: "new-workspace-sheet",
            size: CGSize(width: 520, height: 360)
        )
    }

    func testNotificationBannerAndSettingsScreen() {
        var state = UISnapshotFixtures.appState(ids: ids)
        state.notificationBanners = [
            InAppNotificationBanner(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001010")!,
                title: "Terminal Needs Attention",
                body: "Waiting for input",
                tabID: ids.terminalTab,
                createdAt: fixedDate
            )
        ]
        assertViewSnapshot(
            NotificationBanner(store: store(state)).padding(24),
            named: "notification-banner",
            size: CGSize(width: 520, height: 180)
        )

        assertViewSnapshot(
            SettingsView(store: store(state)),
            named: "settings-screen",
            size: CGSize(width: 620, height: 420)
        )
    }

    private let ids = UIFixtureIDs()
    private let fixedDate = Date(timeIntervalSince1970: 1_782_835_200)

    private var cachedRepo: CachedRepo {
        CachedRepo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001011")!,
            name: "cached-repo",
            bareClonePath: URL(fileURLWithPath: "/tmp/cache/cached-repo.git"),
            remoteURL: "https://example.com/cached-repo.git",
            lastFetched: fixedDate
        )
    }

    private var fullFlowFile: FileDiff {
        FileDiff(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002030")!,
            path: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000002031")!,
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

    private func fullFlowLastTurnFile(fileID: UUID) -> FileDiff {
        FileDiff(
            id: fileID,
            path: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000002032")!,
                    oldStart: 2,
                    oldCount: 2,
                    newStart: 2,
                    newCount: 3,
                    lines: [
                        DiffLine(kind: .context, oldLineNumber: 2, newLineNumber: 2, content: "let title = \"New\""),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 3, content: "let subtitle = \"Workbench\"")
                    ]
                )
            ]
        )
    }

    private func fullFlowAppState(
        repoURL: URL,
        flow: CodeReviewFlowFeature.State
    ) -> AppFeature.State {
        let reviewTab = AppFeature.CodeReviewTabState(id: ids.reviewTab, flow: flow)
        let terminalTab = AppFeature.TerminalTabState(
            id: ids.terminalTab,
            workingDirectory: repoURL,
            outputBuffer: "codex review\n"
        )
        return AppFeature.State(
            workspaces: [
                AppFeature.WorkspaceState(
                    id: ids.workspace,
                    name: "Review Flow",
                    path: repoURL,
                    repos: [
                        WorktreeRef(
                            repoName: "ReviewFixture",
                            bareRepoPath: repoURL,
                            worktreePath: repoURL,
                            branch: "main",
                            remoteURL: "file://review-fixture"
                        )
                    ],
                    tabs: [.terminal(terminalTab), .codeReview(reviewTab)],
                    activeTabID: ids.reviewTab,
                    boardItems: flow.boardItems
                )
            ],
            activeWorkspaceID: ids.workspace,
            isBoardVisible: true
        )
    }

    private func reviewFlowSnapshotView(_ state: AppFeature.State) -> some View {
        let snapshotStore = store(state)
        let workspace = state.workspaces[0]
        let reviewTab: AppFeature.CodeReviewTabState
        if case .codeReview(let tab) = workspace.tabs[1] {
            reviewTab = tab
        } else {
            reviewTab = AppFeature.CodeReviewTabState(id: ids.reviewTab)
        }

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                TabBarView(store: snapshotStore, workspace: workspace)
                Divider()
                CodeReviewView(store: snapshotStore, tab: reviewTab)
            }
            BoardPanel(store: snapshotStore, items: workspace.boardItems)
                .frame(width: 400)
        }
    }

    private func makeCodeReviewRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AvestaCodeFullFlowSnapshots", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try """
        import SwiftUI
        let title = "New"
        let subtitle = "Workbench"

        struct AppView: View {
            var body: some View {
                Text(subtitle)
                Text(title)
            }
        }
        """.write(
            to: sourceDirectory.appendingPathComponent("App.swift"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private func store(_ state: AppFeature.State) -> StoreOf<AppFeature> {
        Store(initialState: state) {
            AppFeature()
        }
    }

    private func assertViewSnapshot<V: View>(
        _ view: V,
        named name: String,
        size: CGSize,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = view
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)
        let controller = NSHostingController(rootView: root)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: .darkAqua)

        assertSnapshot(
            of: controller,
            as: .image(size: size),
            named: name,
            record: snapshotRecordMode,
            file: file,
            testName: testName,
            line: line
        )
    }

    private var snapshotRecordMode: SnapshotTestingConfiguration.Record {
        let rawValue = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] ?? "never"
        return SnapshotTestingConfiguration.Record(rawValue: rawValue) ?? .never
    }
}

private struct UIFixtureIDs {
    let workspace = UUID(uuidString: "00000000-0000-0000-0000-000000002001")!
    let terminalTab = UUID(uuidString: "00000000-0000-0000-0000-000000002002")!
    let reviewTab = UUID(uuidString: "00000000-0000-0000-0000-000000002003")!
    let boardItem = UUID(uuidString: "00000000-0000-0000-0000-000000002004")!
    let file = UUID(uuidString: "00000000-0000-0000-0000-000000002005")!
    let hunk = UUID(uuidString: "00000000-0000-0000-0000-000000002006")!
}

private enum UISnapshotFixtures {
    static func appState(ids: UIFixtureIDs) -> AppFeature.State {
        AppFeature.State(
            workspaces: [
                AppFeature.WorkspaceState(
                    id: ids.workspace,
                    name: "Fixture",
                    path: URL(fileURLWithPath: "/tmp/avestacode-fixture"),
                    tabs: [
                        .terminal(AppFeature.TerminalTabState(
                            id: ids.terminalTab,
                            workingDirectory: URL(fileURLWithPath: "/tmp/avestacode-fixture")
                        ))
                    ],
                    activeTabID: ids.terminalTab
                )
            ],
            activeWorkspaceID: ids.workspace
        )
    }

    static func codeReviewAppState(ids: UIFixtureIDs) -> AppFeature.State {
        var state = appState(ids: ids)
        let flow = CodeReviewFlowFeature.State(
            session: CodeReviewFlowFeature.CodeReviewSessionState(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002008")!,
                diffSpec: "origin/main...HEAD",
                repoPath: URL(fileURLWithPath: "/tmp/avestacode-fixture"),
                files: [file(ids: ids)]
            )
        )
        state.workspaces[0].tabs = [.codeReview(AppFeature.CodeReviewTabState(id: ids.reviewTab, flow: flow))]
        state.workspaces[0].activeTabID = ids.reviewTab
        return state
    }

    static func file(ids: UIFixtureIDs) -> FileDiff {
        FileDiff(
            id: ids.file,
            path: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(
                    id: ids.hunk,
                    oldStart: 1,
                    oldCount: 4,
                    newStart: 1,
                    newCount: 5,
                    lines: [
                        DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "import SwiftUI"),
                        DiffLine(kind: .removed, oldLineNumber: 2, newLineNumber: nil, content: "let title = \"Old\""),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 2, content: "let title = \"New\""),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 3, content: "let subtitle = \"Workbench\""),
                        DiffLine(kind: .context, oldLineNumber: 3, newLineNumber: 4, content: "struct AppView: View {"),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 5, content: "    var body: some View { Text(title) }")
                    ]
                )
            ]
        )
    }
}

private extension AppFeature.WorkspaceState {
    var activeTerminal: AppFeature.TerminalTabState? {
        guard case .terminal(let terminal) = activeTab else { return nil }
        return terminal
    }
}

private struct TerminalStateSnapshotView: View {
    let terminal: AppFeature.TerminalTabState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "terminal")
                Text(terminal.workingDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                Text(terminal.outputBuffer.isEmpty ? "$ " : terminal.outputBuffer)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
