import XCTest
@testable import AvestaCore

final class SQLiteStateRepositoryTests: XCTestCase {
    func testFreshSchemaUsesWALForeignKeysAndCreatesInitialActivityAndTerminal() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "state.sqlite3")
        let repository = try SQLiteStateRepository(databaseURL: url)
        try await repository.initialize()
        let workspace = try await repository.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let loaded = try await repository.loadWorkspaces()

        XCTAssertEqual(loaded.map(\.id), [workspace.id])
        XCTAssertEqual(loaded.first?.name, workspace.name)
        XCTAssertEqual(loaded.first?.path.standardizedFileURL.path, workspace.path.standardizedFileURL.path)
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.tabs.first?.kind, .terminal)
        XCTAssertEqual(workspace.layout.primaryTabID, workspace.tabs.first?.id)
        let terminal = try await repository.terminalSession(tabID: workspace.tabs[0].id)
        XCTAssertNotNil(terminal)

        let database = try SQLiteDatabase(url: url)
        XCTAssertEqual(try database.query("PRAGMA journal_mode").first?["journal_mode"], .text("wal"))
        XCTAssertEqual(try database.query("PRAGMA foreign_keys").first?["foreign_keys"], .integer(1))
        let required = Set(["workspaces", "repository_sources", "workspace_repositories", "workspace_activity_sessions", "tabs", "workspace_layouts", "terminal_sessions", "terminal_events", "review_sessions", "review_snapshots", "review_snapshot_repositories", "review_snapshot_files", "review_annotations", "assistant_threads", "assistant_messages", "notifications", "settings", "schema_migrations"])
        let actual = Set(try database.query("SELECT name FROM sqlite_master WHERE type='table'").compactMap { row -> String? in if case .text(let value) = row["name"] { return value }; return nil })
        XCTAssertTrue(required.isSubset(of: actual))
    }

    func testSnapshotContentIsDeduplicatedAndUnchangedFingerprintDoesNotCreateTimelineNoise() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "state.sqlite3")
        let repository = try SQLiteStateRepository(databaseURL: url); try await repository.initialize()
        var workspace = try await repository.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let source = try await repository.upsertRepositorySource(remoteURL: "https://example.com/repo.git", cachePath: root.appending(path: "repo.git"))
        let worktree = WorkspaceRepositoryRecord(workspaceID: workspace.id, sourceID: source.id, name: "repo", worktreePath: root.appending(path: "workspace/repo"), branch: "main")
        try await repository.addWorkspaceRepository(worktree)
        let reloadedWorkspaces = try await repository.loadWorkspaces()
        workspace = try XCTUnwrap(reloadedWorkspaces.first)
        let file = SnapshotFile(path: "a.swift", status: .modified, oldContent: "old", newContent: String(repeating: "new content\n", count: 500), patch: "+new", fingerprint: "file-fingerprint")
        let snapshot = ReviewSnapshotRecord(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID, fingerprint: "same", reason: "refresh", repositories: [ReviewSnapshotRepository(repositoryID: worktree.id, headOID: "abc", branch: "main", files: [file])])
        let first = try await repository.saveSnapshot(snapshot)
        let second = try await repository.saveSnapshot(ReviewSnapshotRecord(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID, fingerprint: "same", reason: "refresh", repositories: snapshot.repositories))

        XCTAssertEqual(first.id, second.id)
        let timeline = try await repository.snapshots(workspaceID: workspace.id)
        let hydrated = try await repository.loadSnapshot(id: first.id)
        XCTAssertEqual(timeline.count, 1)
        XCTAssertEqual(hydrated?.repositories[0].files[0].newContent, file.newContent)
        let database = try SQLiteDatabase(url: url)
        let blobCount = try database.scalarInt("SELECT COUNT(*) AS value FROM snapshot_blobs")
        XCTAssertEqual(blobCount, 3)
    }

    func testCommentStartsReviewSessionAndPersistsFullAnchorIdentity() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteStateRepository(databaseURL: root.appending(path: "state.sqlite3")); try await repository.initialize()
        let workspace = try await repository.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let source = try await repository.upsertRepositorySource(remoteURL: "https://example.com/repo", cachePath: root.appending(path: "repo.git"))
        let worktree = WorkspaceRepositoryRecord(workspaceID: workspace.id, sourceID: source.id, name: "repo", worktreePath: root.appending(path: "workspace/repo"), branch: "main")
        try await repository.addWorkspaceRepository(worktree)
        let snapshot = try await repository.saveSnapshot(ReviewSnapshotRecord(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID, fingerprint: "fp", reason: "comment", repositories: [ReviewSnapshotRepository(repositoryID: worktree.id, headOID: nil, branch: "main", files: [])]))
        let session = try await repository.ensureReviewSession(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID)
        let annotation = ReviewAnnotation(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID, reviewSessionID: session.id, repositoryID: worktree.id, snapshotID: snapshot.id, kind: .comment, filePath: "a.swift", side: .new, startLine: 4, endLine: 7, anchorFingerprint: "anchor", selectedCode: "code", context: "context", userText: "comment")
        try await repository.saveAnnotation(annotation)

        let active = try await repository.activeReviewSession(workspaceID: workspace.id)
        let annotations = try await repository.annotations(workspaceID: workspace.id)
        XCTAssertEqual(active?.id, session.id)
        let persisted = try XCTUnwrap(annotations.first)
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(persisted.id, annotation.id)
        XCTAssertEqual(persisted.workspaceID, annotation.workspaceID)
        XCTAssertEqual(persisted.activitySessionID, annotation.activitySessionID)
        XCTAssertEqual(persisted.reviewSessionID, annotation.reviewSessionID)
        XCTAssertEqual(persisted.repositoryID, annotation.repositoryID)
        XCTAssertEqual(persisted.snapshotID, annotation.snapshotID)
        XCTAssertEqual(persisted.filePath, annotation.filePath)
        XCTAssertEqual(persisted.side, annotation.side)
        XCTAssertEqual(persisted.startLine, annotation.startLine)
        XCTAssertEqual(persisted.endLine, annotation.endLine)
        XCTAssertEqual(persisted.anchorFingerprint, annotation.anchorFingerprint)
        XCTAssertEqual(persisted.selectedCode, annotation.selectedCode)
        XCTAssertEqual(persisted.context, annotation.context)
        XCTAssertEqual(persisted.userText, annotation.userText)

        try await repository.finishReview(workspaceID: workspace.id, snapshot: snapshot)
        let completedActive = try await repository.activeReviewSession(workspaceID: workspace.id)
        let completedSnapshot = try await repository.lastCompletedReviewSnapshot(workspaceID: workspace.id)
        XCTAssertNil(completedActive)
        XCTAssertEqual(completedSnapshot?.id, snapshot.id)
        let next = try await repository.ensureReviewSession(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID)
        XCTAssertNotEqual(next.id, session.id)
    }

    func testCommentCanBeEditedAndDeletedWithAssistantThreadCascade() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "state.sqlite3")
        let repository = try SQLiteStateRepository(databaseURL: databaseURL)
        try await repository.initialize()
        let workspace = try await repository.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let source = try await repository.upsertRepositorySource(remoteURL: "https://example.com/repo", cachePath: root.appending(path: "repo.git"))
        let worktree = WorkspaceRepositoryRecord(workspaceID: workspace.id, sourceID: source.id, name: "repo", worktreePath: root.appending(path: "workspace/repo"), branch: "main")
        try await repository.addWorkspaceRepository(worktree)
        let snapshot = try await repository.saveSnapshot(ReviewSnapshotRecord(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID, fingerprint: "fp", reason: "comment", repositories: []))
        let session = try await repository.ensureReviewSession(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID)
        let annotation = ReviewAnnotation(workspaceID: workspace.id, activitySessionID: workspace.activitySessionID, reviewSessionID: session.id, repositoryID: worktree.id, snapshotID: snapshot.id, kind: .comment, filePath: "a.swift", side: .new, startLine: 2, endLine: 3, anchorFingerprint: "anchor", selectedCode: "code", context: "context", userText: "original")
        let thread = AssistantThreadRecord(id: UUID(), annotationID: annotation.id, provider: .codex, providerSessionID: nil, model: nil, createdAt: Date())
        let message = AssistantMessageRecord(id: UUID(), threadID: thread.id, role: .assistant, content: "answer", isStreaming: false, errorCode: nil, createdAt: Date())
        try await repository.saveAnnotation(annotation)
        try await repository.saveAssistantThread(thread)
        try await repository.saveAssistantMessage(message)

        try await repository.updateAnnotationText(id: annotation.id, text: "edited")
        let editedAnnotations = try await repository.annotations(workspaceID: workspace.id)
        XCTAssertEqual(editedAnnotations.first?.userText, "edited")

        try await repository.deleteAnnotation(id: annotation.id)
        let remainingAnnotations = try await repository.annotations(workspaceID: workspace.id)
        XCTAssertTrue(remainingAnnotations.isEmpty)
        let database = try SQLiteDatabase(url: databaseURL)
        XCTAssertEqual(try database.scalarInt("SELECT COUNT(*) AS value FROM assistant_threads"), 0)
        XCTAssertEqual(try database.scalarInt("SELECT COUNT(*) AS value FROM assistant_messages"), 0)
    }

    func testRepositoryBankCanReorderAndDeleteSources() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteStateRepository(databaseURL: root.appending(path: "state.sqlite3")); try await repository.initialize()
        let first = try await repository.upsertRepositorySource(remoteURL: "https://github.com/one/first.git", cachePath: root.appending(path: "first.git"))
        let second = try await repository.upsertRepositorySource(remoteURL: "https://github.com/two/second.git", cachePath: root.appending(path: "second.git"))

        try await repository.reorderRepositorySources([second.id, first.id])
        let reordered = try await repository.loadRepositorySources()
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.first?.defaultBaseBranch, "origin/main")

        try await repository.deleteRepositorySource(id: first.id)
        let remaining = try await repository.loadRepositorySources()
        XCTAssertEqual(remaining.map(\.id), [second.id])
    }

    func testClosingActiveTabSelectsNextThenPreviousTabTransactionally() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteStateRepository(databaseURL: root.appending(path: "state.sqlite3"))
        try await repository.initialize()
        let workspace = try await repository.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let first = try XCTUnwrap(workspace.tabs.first)
        let second = TabRecord(workspaceID: workspace.id, kind: .review, title: "Review", sortIndex: 1)
        let third = TabRecord(workspaceID: workspace.id, kind: .terminal, title: "Terminal 2", sortIndex: 2, workingDirectory: workspace.path)
        try await repository.createTab(second, terminal: nil)
        try await repository.createTab(
            third,
            terminal: TerminalSessionRecord(tabID: third.id, workingDirectory: workspace.path)
        )

        try await repository.selectTab(workspaceID: workspace.id, tabID: second.id)
        try await repository.deleteTab(id: second.id)
        var workspaces = try await repository.loadWorkspaces()
        var loaded = try XCTUnwrap(workspaces.first)
        XCTAssertEqual(loaded.tabs.map(\.id), [first.id, third.id])
        XCTAssertEqual(loaded.layout.primaryTabID, third.id)

        try await repository.deleteTab(id: third.id)
        workspaces = try await repository.loadWorkspaces()
        loaded = try XCTUnwrap(workspaces.first)
        XCTAssertEqual(loaded.tabs.map(\.id), [first.id])
        XCTAssertEqual(loaded.layout.primaryTabID, first.id)

        try await repository.deleteTab(id: first.id)
        workspaces = try await repository.loadWorkspaces()
        loaded = try XCTUnwrap(workspaces.first)
        XCTAssertTrue(loaded.tabs.isEmpty)
        XCTAssertNil(loaded.layout.primaryTabID)
    }

    @MainActor
    func testReviewPreferencesPersistAcrossApplicationModelReload() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteStateRepository(databaseURL: root.appending(path: "state.sqlite3"))
        try await repository.initialize()
        let workspace = try await repository.createWorkspace(name: "Demo", path: root.appending(path: "workspace"))
        let filterID = UUID()

        let firstModel = try ApplicationModel(repository: repository)
        await firstModel.load()
        await firstModel.setReviewBaseline(workspaceID: workspace.id, baseline: .branch("origin/main"))
        await firstModel.setReviewMode(workspaceID: workspace.id, mode: .split)
        await firstModel.setReviewRepositoryFilter(workspaceID: workspace.id, repositoryID: filterID)

        let reloadedModel = try ApplicationModel(repository: repository)
        await reloadedModel.load()
        XCTAssertEqual(reloadedModel.reviewStates[workspace.id]?.baseline, .branch("origin/main"))
        XCTAssertEqual(reloadedModel.reviewStates[workspace.id]?.mode, .split)
        XCTAssertEqual(reloadedModel.reviewStates[workspace.id]?.repositoryFilter, filterID)

        await reloadedModel.setReviewRepositoryFilter(workspaceID: workspace.id, repositoryID: nil)
        let clearedModel = try ApplicationModel(repository: repository)
        await clearedModel.load()
        XCTAssertNil(clearedModel.reviewStates[workspace.id]?.repositoryFilter)
    }

    private func temporaryRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "AvestaSQLite-\(UUID())", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
