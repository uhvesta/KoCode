import XCTest
@testable import AvestaCore

@MainActor
final class SessionPersistenceTests: XCTestCase {
    func testAppStateRestoresEmptySessionWithoutCreatingDefaultWorkspace() throws {
        let temp = try temporaryDirectory()
        let store = AppSessionStore(fileURL: temp.appending(path: "session.json"))
        try store.save(AppSessionSnapshot())

        let state = AppState(sessionStore: store)

        XCTAssertTrue(state.workspaces.isEmpty)
        XCTAssertNil(state.activeWorkspaceID)
    }

    func testPersistsTerminalAndCodeReviewTabs() throws {
        let temp = try temporaryDirectory()
        let store = AppSessionStore(fileURL: temp.appending(path: "session.json"))
        let workspacePath = temp.appending(path: "workspace", directoryHint: .isDirectory)
        let terminalResume = TerminalResumeSnapshot(
            agent: "codex",
            sessionID: "session-1",
            command: "codex resume 'session-1'",
            workingDirectory: workspacePath
        )
        let reviewSession = CodeReviewSession(
            diffSpec: "main...HEAD",
            repoPath: workspacePath,
            files: [
                FileDiff(path: "file.swift", status: .modified, hunks: [])
            ],
            comments: [
                ReviewComment(
                    fileID: UUID(),
                    startLine: 1,
                    endLine: 1,
                    highlightedText: "let value = 1",
                    text: "Check this."
                )
            ]
        )
        let workspace = Workspace(
            name: "Work",
            path: workspacePath,
            tabs: [
                TerminalTabModel(workingDirectory: workspacePath, resume: terminalResume),
                CodeReviewTabModel(session: reviewSession)
            ]
        )
        let state = AppState(workspaces: [workspace], activeWorkspaceID: workspace.id, sessionStore: store)

        state.persistSession()
        let restored = AppState(sessionStore: store)

        XCTAssertEqual(restored.workspaces.count, 1)
        XCTAssertEqual(restored.workspaces[0].tabs.count, 2)
        let restoredTerminal = restored.workspaces[0].tabs[0] as? TerminalTabModel
        XCTAssertEqual(restoredTerminal?.resume?.agent, "codex")
        let restoredReview = restored.workspaces[0].tabs[1] as? CodeReviewTabModel
        XCTAssertEqual(restoredReview?.session?.diffSpec, "main...HEAD")
        XCTAssertEqual(restoredReview?.session?.comments.count, 1)
    }

    func testRestoresWorkspaceWithNoTabs() throws {
        let temp = try temporaryDirectory()
        let store = AppSessionStore(fileURL: temp.appending(path: "session.json"))
        let workspace = Workspace(
            name: "Empty",
            path: temp.appending(path: "empty", directoryHint: .isDirectory),
            tabs: [],
            activeTabID: nil,
            createsDefaultTab: false
        )
        let state = AppState(workspaces: [workspace], activeWorkspaceID: workspace.id, sessionStore: store)

        state.persistSession()
        let restored = AppState(sessionStore: store)

        XCTAssertEqual(restored.workspaces.count, 1)
        XCTAssertTrue(restored.workspaces[0].tabs.isEmpty)
        XCTAssertNil(restored.workspaces[0].activeTabID)
    }

    func testCommandCloseKeepsWorkspaceAfterLastTabThenClosesWorkspaceWithoutDeletingFiles() async throws {
        let temp = try temporaryDirectory()
        let store = AppSessionStore(fileURL: temp.appending(path: "session.json"))
        let workspacePath = temp.appending(path: "workspace", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspacePath, withIntermediateDirectories: true)
        let workspace = Workspace(name: "Work", path: workspacePath)
        let state = AppState(workspaces: [workspace], activeWorkspaceID: workspace.id, sessionStore: store)

        await state.closeActiveTabOrCloseEmptyWorkspace()

        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertTrue(state.workspaces[0].tabs.isEmpty)

        await state.closeActiveTabOrCloseEmptyWorkspace()

        XCTAssertTrue(state.workspaces.isEmpty)
        XCTAssertNil(state.activeWorkspaceID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspacePath.path))
    }

    func testAgentResumeCommandBuilders() {
        let support = TerminalAgentResumeSupport(copilotResumeTemplate: "copilot --resume {{sessionId}}")

        XCTAssertEqual(support.sessionID(from: ["claude", "--resume", "abc"], agent: .claude), "abc")
        XCTAssertEqual(support.resumeCommand(agent: .claude, sessionID: "abc"), "claude --resume 'abc'")
        XCTAssertEqual(support.sessionID(from: ["codex", "resume", "def"], agent: .codex), "def")
        XCTAssertEqual(support.resumeCommand(agent: .codex, sessionID: "def"), "codex resume 'def'")
        XCTAssertEqual(support.sessionID(from: ["copilot", "--session-id=ghi"], agent: .copilot), "ghi")
        XCTAssertEqual(support.resumeCommand(agent: .copilot, sessionID: "ghi"), "copilot --resume 'ghi'")
        XCTAssertEqual(TerminalAgentResumeSupport().resumeCommand(agent: .copilot, sessionID: "ghi"), "copilot --resume 'ghi'")
    }

    func testAgentEventClassifierClassifiesStructuredAndPlainOutput() {
        let classifier = TerminalAgentEventClassifier()

        XCTAssertEqual(classifier.event(from: #"{"hookEventName":"Stop","message":"turn complete"}"#)?.kind, .done)
        XCTAssertEqual(classifier.event(from: #"{"hookEventName":"PermissionRequest","message":"Approve command?"}"#)?.kind, .needsInput)
        XCTAssertEqual(classifier.event(from: "waiting for user input\n")?.kind, .needsInput)
        XCTAssertEqual(classifier.event(from: "Unhandled exception\n")?.kind, .error)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AvestaCodeSessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
