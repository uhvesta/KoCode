import XCTest
@testable import AvestaCore

final class WorkspaceReviewBundleTests: XCTestCase {
    func testBundleUsesWorkspaceRepositoryOrderAndIncludesFullRanges() {
        let workspaceID = UUID()
        let firstRepository = repository(workspaceID: workspaceID, name: "first", sortIndex: 0)
        let secondRepository = repository(workspaceID: workspaceID, name: "second", sortIndex: 1)
        let workspace = WorkspaceRecord(
            id: workspaceID,
            name: "Demo",
            path: URL(fileURLWithPath: "/tmp/Demo"),
            repositories: [firstRepository, secondRepository]
        )
        let activityID = UUID()
        let reviewID = UUID()
        let snapshotID = UUID()
        let laterRepositoryComment = annotation(
            workspaceID: workspaceID,
            activityID: activityID,
            reviewID: reviewID,
            snapshotID: snapshotID,
            repositoryID: secondRepository.id,
            file: "z.swift",
            side: .new,
            lines: 9...10,
            code: "let z = 1\nlet y = 2",
            text: "Please simplify this."
        )
        var firstRepositoryComment = annotation(
            workspaceID: workspaceID,
            activityID: activityID,
            reviewID: reviewID,
            snapshotID: snapshotID,
            repositoryID: firstRepository.id,
            file: "a.swift",
            side: .old,
            lines: 2...2,
            code: "removedCall()",
            text: "Why was this removed?"
        )
        firstRepositoryComment.kind = .question
        firstRepositoryComment.isOutdated = true

        let bundle = WorkspaceReviewBundleFormatter.format(
            workspace: workspace,
            annotations: [laterRepositoryComment, firstRepositoryComment]
        )

        XCTAssertTrue(bundle.hasPrefix("Workspace review feedback for \"Demo\""))
        XCTAssertLessThan(try XCTUnwrap(bundle.range(of: "## 1. first")).lowerBound, try XCTUnwrap(bundle.range(of: "## 2. second")).lowerBound)
        XCTAssertTrue(bundle.contains("a.swift (old line 2) [outdated anchor]"))
        XCTAssertTrue(bundle.contains("Question:\nWhy was this removed?"))
        XCTAssertTrue(bundle.contains("z.swift (new lines 9-10)"))
        XCTAssertTrue(bundle.contains("    let z = 1\n    let y = 2"))
    }

    func testCommentNavigationWrapsInReviewOrder() {
        let workspaceID = UUID()
        let activityID = UUID()
        let reviewID = UUID()
        let snapshotID = UUID()
        let repositoryID = UUID()
        let first = annotation(workspaceID: workspaceID, activityID: activityID, reviewID: reviewID, snapshotID: snapshotID, repositoryID: repositoryID, file: "a.swift", side: .new, lines: 1...1, code: "a", text: "first")
        let second = annotation(workspaceID: workspaceID, activityID: activityID, reviewID: reviewID, snapshotID: snapshotID, repositoryID: repositoryID, file: "b.swift", side: .new, lines: 2...2, code: "b", text: "second")

        XCTAssertEqual(ReviewAnnotationNavigation.adjacentID(in: [first, second], currentID: first.id, offset: 1), second.id)
        XCTAssertEqual(ReviewAnnotationNavigation.adjacentID(in: [first, second], currentID: second.id, offset: 1), first.id)
        XCTAssertEqual(ReviewAnnotationNavigation.adjacentID(in: [first, second], currentID: first.id, offset: -1), second.id)
        XCTAssertNil(ReviewAnnotationNavigation.adjacentID(in: [], currentID: nil, offset: 1))
    }

    @MainActor
    func testBundleCanTargetOneSpecificTerminalWithoutAppendingEnter() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repositoryStore = try SQLiteStateRepository(databaseURL: root.appending(path: "state.sqlite3"))
        try await repositoryStore.initialize()
        let created = try await repositoryStore.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let secondTerminal = TabRecord(workspaceID: created.id, kind: .terminal, title: "Target", sortIndex: 1, workingDirectory: created.path)
        try await repositoryStore.createTab(secondTerminal, terminal: TerminalSessionRecord(tabID: secondTerminal.id, workingDirectory: created.path))
        let model = try ApplicationModel(repository: repositoryStore)
        await model.load()
        let workspace = try XCTUnwrap(model.workspaces.first)
        let annotation = annotation(
            workspaceID: workspace.id,
            activityID: workspace.activitySessionID,
            reviewID: UUID(),
            snapshotID: UUID(),
            repositoryID: UUID(),
            file: "a.swift",
            side: .new,
            lines: 1...1,
            code: "value",
            text: "Fix this."
        )

        XCTAssertTrue(model.sendReviewBundleToTerminal(workspaceID: workspace.id, annotations: [annotation], targetTabID: secondTerminal.id))
        let request = try XCTUnwrap(model.pendingTerminalInput[secondTerminal.id])
        XCTAssertEqual(request.text, WorkspaceReviewBundleFormatter.format(workspace: workspace, annotations: [annotation]))
        XCTAssertFalse(request.text.hasSuffix("\n"))
        XCTAssertNil(model.pendingTerminalInput[workspace.tabs.first!.id])
    }

    private func repository(workspaceID: UUID, name: String, sortIndex: Int) -> WorkspaceRepositoryRecord {
        WorkspaceRepositoryRecord(
            workspaceID: workspaceID,
            sourceID: UUID(),
            name: name,
            worktreePath: URL(fileURLWithPath: "/tmp/\(name)"),
            branch: "main",
            sortIndex: sortIndex
        )
    }

    private func annotation(
        workspaceID: UUID,
        activityID: UUID,
        reviewID: UUID,
        snapshotID: UUID,
        repositoryID: UUID,
        file: String,
        side: DiffSide,
        lines: ClosedRange<Int>,
        code: String,
        text: String
    ) -> ReviewAnnotation {
        ReviewAnnotation(
            workspaceID: workspaceID,
            activitySessionID: activityID,
            reviewSessionID: reviewID,
            repositoryID: repositoryID,
            snapshotID: snapshotID,
            kind: .comment,
            filePath: file,
            side: side,
            startLine: lines.lowerBound,
            endLine: lines.upperBound,
            anchorFingerprint: "anchor",
            selectedCode: code,
            context: "context",
            userText: text
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AvestaReviewBundle-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
