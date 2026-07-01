import ComposableArchitecture
import SnapshotTesting
import XCTest
@testable import AvestaCore

@MainActor
final class AppFeatureActionSnapshotTests: XCTestCase {
    func testWorkspaceTabBoardAndPersistenceActionSequence() async {
        let ids = FixtureIDs()
        let now = Date(timeIntervalSince1970: 1_782_835_200)
        let store = TestStore(initialState: ReducerSnapshotFixtures.appState(ids: ids)) {
            AppFeature()
        }
        store.exhaustivity = .off

        var timeline: [String] = [
            ReducerSnapshotRenderer.render(store.state, label: "initial")
        ]

        await store.send(.terminalOutput(tabID: ids.terminalTab, output: "build failed\nline 42"))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "terminal output"))

        await store.send(.sendActiveTerminalOutputToBoard(id: ids.boardItem, createdAt: now))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "send terminal output to board"))

        await store.send(.addCodeReviewTab(id: ids.reviewTab))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "create code review tab"))

        await store.send(.selectTab(index: 0))
        await store.send(.pasteMostRecentBoardItemToActiveTerminal)
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "paste board item into terminal"))

        await store.send(.toggleBoard)
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "toggle board"))

        await store.send(.closeActiveTabOrWorkspace)
        await store.send(.closeActiveTabOrWorkspace)
        await store.send(.closeActiveTabOrWorkspace)
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "cmd-w closes tabs then workspace"))

        assertSnapshot(
            of: timeline.joined(separator: "\n\n"),
            as: .lines,
            named: "workspace-tab-board-persistence-actions",
            record: snapshotRecordMode
        )
    }

    func testCodeReviewCommentNavigationAndBoardActionSequence() async {
        let ids = FixtureIDs()
        let now = Date(timeIntervalSince1970: 1_782_835_200)
        let store = TestStore(initialState: ReducerSnapshotFixtures.codeReviewAppState(ids: ids)) {
            AppFeature()
        }
        store.exhaustivity = .off

        var timeline: [String] = [
            ReducerSnapshotRenderer.render(store.state, label: "initial code review")
        ]

        await store.send(AppFeature.Action.codeReview(tabID: ids.reviewTab, .nextChangeButtonTapped))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "next change"))

        await store.send(AppFeature.Action.codeReview(tabID: ids.reviewTab, .previousChangeButtonTapped))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "previous change"))

        await store.send(AppFeature.Action.codeReview(
            tabID: ids.reviewTab,
            .selectLine(CodeReviewFlowFeature.PendingLine(
                fileID: ids.file,
                lineNumber: 2,
                content: "let title = \"New\""
            ))
        ))
        await store.send(AppFeature.Action.codeReview(tabID: ids.reviewTab, .commentTextChanged("Prefer a localized title here.")))
        await store.send(AppFeature.Action.codeReview(tabID: ids.reviewTab, .saveCommentButtonTapped(id: ids.comment, createdAt: now)))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "add inline comment"))

        await store.send(AppFeature.Action.codeReview(tabID: ids.reviewTab, .sendReviewToBoardButtonTapped(id: ids.boardItem, now: now)))
        timeline.append(ReducerSnapshotRenderer.render(store.state, label: "send review to board"))

        assertSnapshot(
            of: timeline.joined(separator: "\n\n"),
            as: .lines,
            named: "code-review-actions",
            record: snapshotRecordMode
        )
    }

    private var snapshotRecordMode: SnapshotTestingConfiguration.Record {
        let rawValue = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"] ?? "never"
        return SnapshotTestingConfiguration.Record(rawValue: rawValue) ?? .never
    }
}

struct FixtureIDs {
    let workspace = UUID(uuidString: "00000000-0000-0000-0000-000000001001")!
    let terminalTab = UUID(uuidString: "00000000-0000-0000-0000-000000001002")!
    let reviewTab = UUID(uuidString: "00000000-0000-0000-0000-000000001003")!
    let boardItem = UUID(uuidString: "00000000-0000-0000-0000-000000001004")!
    let file = UUID(uuidString: "00000000-0000-0000-0000-000000001005")!
    let hunk = UUID(uuidString: "00000000-0000-0000-0000-000000001006")!
    let comment = UUID(uuidString: "00000000-0000-0000-0000-000000001007")!
}

enum ReducerSnapshotFixtures {
    static func appState(ids: FixtureIDs) -> AppFeature.State {
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

    static func codeReviewAppState(ids: FixtureIDs) -> AppFeature.State {
        var state = appState(ids: ids)
        let flow = CodeReviewFlowFeature.State(
            session: CodeReviewFlowFeature.CodeReviewSessionState(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001008")!,
                diffSpec: "origin/main...HEAD",
                repoPath: URL(fileURLWithPath: "/tmp/avestacode-fixture"),
                files: [file(ids: ids)]
            )
        )
        state.workspaces[0].tabs = [.codeReview(AppFeature.CodeReviewTabState(id: ids.reviewTab, flow: flow))]
        state.workspaces[0].activeTabID = ids.reviewTab
        return state
    }

    static func file(ids: FixtureIDs) -> FileDiff {
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

enum ReducerSnapshotRenderer {
    static func render(_ state: AppFeature.State, label: String) -> String {
        var lines: [String] = ["# \(label)"]
        lines.append("activeWorkspace=\(state.activeWorkspaceID?.uuidString ?? "nil")")
        lines.append("boardVisible=\(state.isBoardVisible)")
        lines.append("globalBoardItems=\(state.globalBoardItems.count)")
        lines.append("badges=\(state.notificationBadges.map { "\($0.key.uuidString):\($0.value)" }.sorted().joined(separator: ","))")
        lines.append("banners=\(state.notificationBanners.map(\.title).joined(separator: ","))")
        lines.append("persisted=\(state.lastPersistenceSnapshot != nil)")

        for workspace in state.workspaces {
            lines.append("workspace \(workspace.id.uuidString) \(workspace.name) activeTab=\(workspace.activeTabID?.uuidString ?? "nil") repos=\(workspace.repos.count) board=\(workspace.boardItems.count)")
            for item in workspace.boardItems {
                lines.append("  boardItem \(item.id.uuidString) source=\(item.source) content=\(oneLine(item.content))")
            }
            for tab in workspace.tabs {
                switch tab {
                case .terminal(let terminal):
                    lines.append("  terminal \(terminal.id.uuidString) title=\(terminal.title) output=\(oneLine(terminal.outputBuffer)) pendingPaste=\(oneLine(terminal.pendingPaste ?? "nil"))")
                case .codeReview(let review):
                    lines.append("  codeReview \(review.id.uuidString) title=\(review.title)")
                    if let flow = review.flow {
                        lines.append("    diff=\(flow.session.diffSpec) activeFile=\(flow.session.activeFileIndex) nav=\(flow.navigation.statusText) comments=\(flow.session.comments.count) selectedLine=\(flow.selectedLine?.lineNumber.description ?? "nil")")
                        for comment in flow.session.comments {
                            lines.append("    comment \(comment.id.uuidString) line=\(comment.startLine) text=\(oneLine(comment.text))")
                        }
                    } else {
                        lines.append("    noSession")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func oneLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
