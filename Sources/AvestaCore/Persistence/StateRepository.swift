import Compression
import CryptoKit
import Foundation

public protocol StateRepository: Sendable {
    func initialize() async throws
    func loadWorkspaces() async throws -> [WorkspaceRecord]
    func loadRepositorySources() async throws -> [RepositorySourceRecord]
    func createWorkspace(name: String, path: URL) async throws -> WorkspaceRecord
    func renameWorkspace(id: UUID, name: String) async throws
    func reorderWorkspaces(_ ids: [UUID]) async throws
    func deleteWorkspace(id: UUID) async throws
    func upsertRepositorySource(remoteURL: String, cachePath: URL, defaultBaseBranch: String) async throws -> RepositorySourceRecord
    func updateSourceFetchDate(id: UUID, date: Date) async throws
    func updateSourceDefaultBaseBranch(id: UUID, branch: String) async throws
    func reorderRepositorySources(_ ids: [UUID]) async throws
    func deleteRepositorySource(id: UUID) async throws
    func addWorkspaceRepository(_ repository: WorkspaceRepositoryRecord) async throws
    func reorderWorkspaceRepositories(workspaceID: UUID, ids: [UUID]) async throws
    func removeWorkspaceRepository(id: UUID) async throws
    func createTab(_ tab: TabRecord, terminal: TerminalSessionRecord?) async throws
    func renameTab(id: UUID, title: String) async throws
    func reorderTabs(workspaceID: UUID, ids: [UUID]) async throws
    func selectTab(workspaceID: UUID, tabID: UUID) async throws
    func dockCompanion(workspaceID: UUID, tabID: UUID, ratio: Double) async throws
    func undockCompanion(workspaceID: UUID) async throws
    func updateSplit(workspaceID: UUID, ratio: Double, focusedTabID: UUID?) async throws
    func deleteTab(id: UUID) async throws
    func terminalSession(tabID: UUID) async throws -> TerminalSessionRecord?
    func updateTerminalScrollback(tabID: UUID, policy: ScrollbackPolicy) async throws
    func saveTerminalEvent(tabID: UUID, kind: String, summary: String, metadata: String?) async throws
    func startActivitySession(workspaceID: UUID, snapshot: ReviewSnapshotRecord?) async throws -> WorkspaceActivitySession
    func activeReviewSession(workspaceID: UUID) async throws -> ReviewSessionRecord?
    func lastCompletedReviewSnapshot(workspaceID: UUID) async throws -> ReviewSnapshotRecord?
    func activityBaselineSnapshot(workspaceID: UUID) async throws -> ReviewSnapshotRecord?
    func ensureReviewSession(workspaceID: UUID, activitySessionID: UUID) async throws -> ReviewSessionRecord
    func finishReview(workspaceID: UUID, snapshot: ReviewSnapshotRecord) async throws
    func saveSnapshot(_ snapshot: ReviewSnapshotRecord) async throws -> ReviewSnapshotRecord
    func snapshots(workspaceID: UUID) async throws -> [ReviewSnapshotRecord]
    func loadSnapshot(id: UUID) async throws -> ReviewSnapshotRecord?
    func saveAnnotation(_ annotation: ReviewAnnotation) async throws
    func annotations(workspaceID: UUID) async throws -> [ReviewAnnotation]
    func updateAnnotationText(id: UUID, text: String) async throws
    func deleteAnnotation(id: UUID) async throws
    func markAnnotationOutdated(id: UUID, isOutdated: Bool) async throws
    func saveAssistantThread(_ thread: AssistantThreadRecord) async throws
    func saveAssistantMessage(_ message: AssistantMessageRecord) async throws
    func saveNotification(_ notification: NotificationRecord) async throws
    func setSettingData(_ value: Data, forKey key: String) async throws
    func settingData(forKey key: String) async throws -> Data?
    func removeSetting(forKey key: String) async throws
}

public actor SQLiteStateRepository: StateRepository {
    private let database: SQLiteDatabase

    public init(databaseURL: URL) throws {
        database = try SQLiteDatabase(url: databaseURL)
    }

    public func initialize() throws {
        try AvestaSchema.migrate(database)
    }

    public func loadWorkspaces() throws -> [WorkspaceRecord] {
        let workspaceRows = try database.query("SELECT * FROM workspaces ORDER BY sort_index, created_at")
        return try workspaceRows.compactMap { row in
            guard let id = row.uuid("id"), let name = row.text("name"), let path = row.text("path") else { return nil }
            let repositories = try loadRepositories(workspaceID: id)
            let tabs = try loadTabs(workspaceID: id)
            let layout = try loadLayout(workspaceID: id)
            let activityID = row.uuid("active_activity_session_id") ?? UUID()
            return WorkspaceRecord(
                id: id,
                name: name,
                path: URL(fileURLWithPath: path, isDirectory: true),
                sortIndex: row.integer("sort_index"),
                createdAt: row.date("created_at"),
                repositories: repositories,
                tabs: tabs,
                layout: layout,
                activitySessionID: activityID
            )
        }
    }

    public func loadRepositorySources() throws -> [RepositorySourceRecord] {
        try database.query("SELECT * FROM repository_sources ORDER BY sort_index, created_at").compactMap { row in
            guard let id = row.uuid("id"),
                  let canonical = row.text("canonical_remote_url"),
                  let display = row.text("display_remote_url"),
                  let cachePath = row.text("cache_path") else { return nil }
            return RepositorySourceRecord(
                id: id,
                canonicalRemoteURL: canonical,
                displayRemoteURL: display,
                cachePath: URL(fileURLWithPath: cachePath, isDirectory: true),
                sortIndex: row.integer("sort_index"),
                createdAt: row.date("created_at"),
                lastFetchedAt: row.optionalDate("last_fetched_at"),
                defaultBaseBranch: row.text("default_base_branch") ?? "origin/main"
            )
        }
    }

    public func createWorkspace(name: String, path: URL) throws -> WorkspaceRecord {
        let id = UUID()
        let activityID = UUID()
        let tabID = UUID()
        let now = Date()
        let nextIndex = Int(try database.scalarInt("SELECT COALESCE(MAX(sort_index), -1) + 1 AS value FROM workspaces") ?? 0)
        let tab = TabRecord(id: tabID, workspaceID: id, kind: .terminal, title: "Terminal", workingDirectory: path)
        let terminal = TerminalSessionRecord(tabID: tabID, workingDirectory: path)
        let layout = WorkspaceLayoutRecord(workspaceID: id, primaryTabID: tabID, focusedTabID: tabID)

        try database.transaction {
            try database.execute(
                "INSERT INTO workspaces(id,name,path,sort_index,created_at,active_activity_session_id) VALUES(?,?,?,?,?,?)",
                bindings: [.uuid(id), .text(name), .text(path.path), .integer(Int64(nextIndex)), .date(now), .uuid(activityID)]
            )
            try database.execute(
                "INSERT INTO workspace_activity_sessions(id,workspace_id,started_at) VALUES(?,?,?)",
                bindings: [.uuid(activityID), .uuid(id), .date(now)]
            )
            try insertTab(tab)
            try insertTerminal(terminal)
            try insertLayout(layout)
        }
        return WorkspaceRecord(id: id, name: name, path: path, sortIndex: nextIndex, createdAt: now, tabs: [tab], layout: layout, activitySessionID: activityID)
    }

    public func renameWorkspace(id: UUID, name: String) throws {
        try database.execute("UPDATE workspaces SET name=? WHERE id=?", bindings: [.text(name), .uuid(id)])
    }

    public func reorderWorkspaces(_ ids: [UUID]) throws {
        try database.transaction {
            for (index, id) in ids.enumerated() {
                try database.execute("UPDATE workspaces SET sort_index=? WHERE id=?", bindings: [.integer(Int64(index)), .uuid(id)])
            }
        }
    }

    public func deleteWorkspace(id: UUID) throws {
        try database.execute("DELETE FROM workspaces WHERE id=?", bindings: [.uuid(id)])
    }

    public func upsertRepositorySource(remoteURL: String, cachePath: URL, defaultBaseBranch: String = "origin/main") throws -> RepositorySourceRecord {
        let canonical = Self.canonicalRemoteURL(remoteURL)
        if let existing = try loadRepositorySources().first(where: { $0.canonicalRemoteURL == canonical }) { return existing }
        let nextIndex = Int(try database.scalarInt("SELECT COALESCE(MAX(sort_index), -1) + 1 AS value FROM repository_sources") ?? 0)
        let source = RepositorySourceRecord(canonicalRemoteURL: canonical, displayRemoteURL: remoteURL, cachePath: cachePath, sortIndex: nextIndex, defaultBaseBranch: defaultBaseBranch)
        try database.execute(
            "INSERT INTO repository_sources(id,canonical_remote_url,display_remote_url,cache_path,sort_index,created_at,default_base_branch) VALUES(?,?,?,?,?,?,?)",
            bindings: [.uuid(source.id), .text(source.canonicalRemoteURL), .text(source.displayRemoteURL), .text(source.cachePath.path), .integer(Int64(source.sortIndex)), .date(source.createdAt), .text(source.defaultBaseBranch)]
        )
        return source
    }

    public func updateSourceFetchDate(id: UUID, date: Date) throws {
        try database.execute("UPDATE repository_sources SET last_fetched_at=? WHERE id=?", bindings: [.date(date), .uuid(id)])
    }

    public func updateSourceDefaultBaseBranch(id: UUID, branch: String) throws {
        try database.execute("UPDATE repository_sources SET default_base_branch=? WHERE id=?", bindings: [.text(branch), .uuid(id)])
    }

    public func reorderRepositorySources(_ ids: [UUID]) throws {
        try database.transaction {
            for (index, id) in ids.enumerated() {
                try database.execute("UPDATE repository_sources SET sort_index=? WHERE id=?", bindings: [.integer(Int64(index)), .uuid(id)])
            }
        }
    }

    public func deleteRepositorySource(id: UUID) throws {
        try database.execute("DELETE FROM repository_sources WHERE id=?", bindings: [.uuid(id)])
    }

    public func addWorkspaceRepository(_ repository: WorkspaceRepositoryRecord) throws {
        try database.execute(
            "INSERT INTO workspace_repositories(id,workspace_id,source_id,name,worktree_path,branch,base_branch,sort_index) VALUES(?,?,?,?,?,?,?,?)",
            bindings: [.uuid(repository.id), .uuid(repository.workspaceID), .uuid(repository.sourceID), .text(repository.name), .text(repository.worktreePath.path), .text(repository.branch), repository.baseBranch.map(SQLiteValue.text) ?? .null, .integer(Int64(repository.sortIndex))]
        )
    }

    public func reorderWorkspaceRepositories(workspaceID: UUID, ids: [UUID]) throws {
        try database.transaction {
            for (index, id) in ids.enumerated() {
                try database.execute("UPDATE workspace_repositories SET sort_index=? WHERE id=? AND workspace_id=?", bindings: [.integer(Int64(index)), .uuid(id), .uuid(workspaceID)])
            }
        }
    }

    public func removeWorkspaceRepository(id: UUID) throws {
        try database.execute("DELETE FROM workspace_repositories WHERE id=?", bindings: [.uuid(id)])
    }

    public func createTab(_ tab: TabRecord, terminal: TerminalSessionRecord?) throws {
        try database.transaction {
            try insertTab(tab)
            if let terminal { try insertTerminal(terminal) }
        }
    }

    public func renameTab(id: UUID, title: String) throws {
        try database.execute("UPDATE tabs SET title=? WHERE id=?", bindings: [.text(title), .uuid(id)])
    }

    public func reorderTabs(workspaceID: UUID, ids: [UUID]) throws {
        try database.transaction {
            for (index, id) in ids.enumerated() {
                try database.execute("UPDATE tabs SET sort_index=? WHERE id=? AND workspace_id=?", bindings: [.integer(Int64(index)), .uuid(id), .uuid(workspaceID)])
            }
        }
    }

    public func selectTab(workspaceID: UUID, tabID: UUID) throws {
        try database.execute("UPDATE workspace_layouts SET primary_tab_id=?, focused_tab_id=? WHERE workspace_id=?", bindings: [.uuid(tabID), .uuid(tabID), .uuid(workspaceID)])
    }

    public func dockCompanion(workspaceID: UUID, tabID: UUID, ratio: Double) throws {
        try database.execute("UPDATE workspace_layouts SET companion_tab_id=?, focused_tab_id=?, split_ratio=? WHERE workspace_id=?", bindings: [.uuid(tabID), .uuid(tabID), .real(clampedRatio(ratio)), .uuid(workspaceID)])
    }

    public func undockCompanion(workspaceID: UUID) throws {
        try database.execute("UPDATE workspace_layouts SET companion_tab_id=NULL, focused_tab_id=primary_tab_id WHERE workspace_id=?", bindings: [.uuid(workspaceID)])
    }

    public func updateSplit(workspaceID: UUID, ratio: Double, focusedTabID: UUID?) throws {
        try database.execute("UPDATE workspace_layouts SET split_ratio=?, focused_tab_id=? WHERE workspace_id=?", bindings: [.real(clampedRatio(ratio)), focusedTabID.map(SQLiteValue.uuid) ?? .null, .uuid(workspaceID)])
    }

    public func deleteTab(id: UUID) throws {
        try database.transaction {
            guard let tab = try database.query(
                "SELECT workspace_id, sort_index FROM tabs WHERE id=?",
                bindings: [.uuid(id)]
            ).first, let workspaceID = tab.text("workspace_id") else { return }

            let remaining = try database.query(
                "SELECT id, sort_index FROM tabs WHERE workspace_id=? AND id<>? ORDER BY sort_index",
                bindings: [.text(workspaceID), .uuid(id)]
            )
            let closingIndex = tab.integer("sort_index")
            let replacementID = remaining.first(where: { $0.integer("sort_index") > closingIndex })?.text("id")
                ?? remaining.last?.text("id")
            let layout = try database.query(
                "SELECT primary_tab_id, companion_tab_id, focused_tab_id FROM workspace_layouts WHERE workspace_id=?",
                bindings: [.text(workspaceID)]
            ).first
            let currentPrimary = layout?.text("primary_tab_id")
            var nextPrimary = currentPrimary == id.uuidString ? replacementID : currentPrimary
            var nextCompanion = layout?.text("companion_tab_id")
            if nextCompanion == id.uuidString || nextCompanion == nextPrimary { nextCompanion = nil }
            if nextPrimary == nil { nextPrimary = remaining.first?.text("id") }
            let currentFocused = layout?.text("focused_tab_id")
            let nextFocused = currentFocused == id.uuidString ? nextPrimary : currentFocused

            try database.execute(
                "UPDATE workspace_layouts SET primary_tab_id=?, companion_tab_id=?, focused_tab_id=? WHERE workspace_id=?",
                bindings: [
                    nextPrimary.map(SQLiteValue.text) ?? .null,
                    nextCompanion.map(SQLiteValue.text) ?? .null,
                    nextFocused.map(SQLiteValue.text) ?? .null,
                    .text(workspaceID),
                ]
            )
            try database.execute("DELETE FROM tabs WHERE id=?", bindings: [.uuid(id)])
        }
    }

    public func terminalSession(tabID: UUID) throws -> TerminalSessionRecord? {
        guard let row = try database.query("SELECT * FROM terminal_sessions WHERE tab_id=?", bindings: [.uuid(tabID)]).first,
              let path = row.text("working_directory") else { return nil }
        let policy: ScrollbackPolicy
        switch row.text("scrollback_kind") {
        case "disabled": policy = .disabled
        case "unlimited": policy = .unlimited
        default: policy = .limited(lines: row.integer("scrollback_lines"))
        }
        return TerminalSessionRecord(tabID: tabID, workingDirectory: URL(fileURLWithPath: path, isDirectory: true), startupInput: row.text("startup_input"), resumeProvider: row.text("resume_provider"), resumeIdentifier: row.text("resume_identifier"), scrollback: policy)
    }

    public func updateTerminalScrollback(tabID: UUID, policy: ScrollbackPolicy) throws {
        let kind: String
        let lines: SQLiteValue
        switch policy {
        case .disabled: kind = "disabled"; lines = .null
        case .unlimited: kind = "unlimited"; lines = .null
        case .limited(let count): kind = "limited"; lines = .integer(Int64(max(1, count)))
        }
        try database.execute("UPDATE terminal_sessions SET scrollback_kind=?, scrollback_lines=? WHERE tab_id=?", bindings: [.text(kind), lines, .uuid(tabID)])
    }

    public func saveTerminalEvent(tabID: UUID, kind: String, summary: String, metadata: String?) throws {
        try database.execute("INSERT INTO terminal_events(id,tab_id,kind,summary,metadata,created_at) VALUES(?,?,?,?,?,?)", bindings: [.uuid(UUID()), .uuid(tabID), .text(kind), .text(summary), metadata.map(SQLiteValue.text) ?? .null, .date(Date())])
    }

    public func startActivitySession(workspaceID: UUID, snapshot: ReviewSnapshotRecord?) throws -> WorkspaceActivitySession {
        let session = WorkspaceActivitySession(workspaceID: workspaceID, baselineSnapshotID: snapshot?.id)
        try database.transaction {
            if let snapshot { _ = try persistSnapshot(snapshot) }
            try database.execute("UPDATE workspace_activity_sessions SET ended_at=? WHERE workspace_id=? AND ended_at IS NULL", bindings: [.date(session.startedAt), .uuid(workspaceID)])
            try database.execute("INSERT INTO workspace_activity_sessions(id,workspace_id,started_at,baseline_snapshot_id) VALUES(?,?,?,?)", bindings: [.uuid(session.id), .uuid(workspaceID), .date(session.startedAt), session.baselineSnapshotID.map(SQLiteValue.uuid) ?? .null])
            try database.execute("UPDATE workspaces SET active_activity_session_id=? WHERE id=?", bindings: [.uuid(session.id), .uuid(workspaceID)])
        }
        return session
    }

    public func activeReviewSession(workspaceID: UUID) throws -> ReviewSessionRecord? {
        guard let row = try database.query("SELECT * FROM review_sessions WHERE workspace_id=? AND completed_at IS NULL ORDER BY started_at DESC LIMIT 1", bindings: [.uuid(workspaceID)]).first else { return nil }
        return reviewSession(from: row)
    }

    public func lastCompletedReviewSnapshot(workspaceID: UUID) throws -> ReviewSnapshotRecord? {
        guard let id = try database.query("SELECT final_snapshot_id FROM review_sessions WHERE workspace_id=? AND completed_at IS NOT NULL AND final_snapshot_id IS NOT NULL ORDER BY completed_at DESC LIMIT 1", bindings: [.uuid(workspaceID)]).first?.uuid("final_snapshot_id") else { return nil }
        return try loadSnapshot(id: id)
    }

    public func activityBaselineSnapshot(workspaceID: UUID) throws -> ReviewSnapshotRecord? {
        guard let id = try database.query("SELECT baseline_snapshot_id FROM workspace_activity_sessions WHERE workspace_id=? AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1", bindings: [.uuid(workspaceID)]).first?.uuid("baseline_snapshot_id") else { return nil }
        return try loadSnapshot(id: id)
    }

    public func ensureReviewSession(workspaceID: UUID, activitySessionID: UUID) throws -> ReviewSessionRecord {
        if let active = try activeReviewSession(workspaceID: workspaceID) { return active }
        let review = ReviewSessionRecord(workspaceID: workspaceID, activitySessionID: activitySessionID)
        try database.execute("INSERT INTO review_sessions(id,workspace_id,activity_session_id,started_at) VALUES(?,?,?,?)", bindings: [.uuid(review.id), .uuid(workspaceID), .uuid(activitySessionID), .date(review.startedAt)])
        return review
    }

    public func finishReview(workspaceID: UUID, snapshot: ReviewSnapshotRecord) throws {
        try database.transaction {
            let stored = try persistSnapshot(snapshot)
            try database.execute("UPDATE review_sessions SET completed_at=?, final_snapshot_id=? WHERE workspace_id=? AND completed_at IS NULL", bindings: [.date(Date()), .uuid(stored.id), .uuid(workspaceID)])
        }
    }

    public func saveSnapshot(_ snapshot: ReviewSnapshotRecord) throws -> ReviewSnapshotRecord {
        try database.transaction { try persistSnapshot(snapshot) }
    }

    public func snapshots(workspaceID: UUID) throws -> [ReviewSnapshotRecord] {
        try database.query("SELECT * FROM review_snapshots WHERE workspace_id=? ORDER BY created_at DESC", bindings: [.uuid(workspaceID)]).compactMap(snapshotHeader)
    }

    public func loadSnapshot(id: UUID) throws -> ReviewSnapshotRecord? {
        guard let row = try database.query("SELECT * FROM review_snapshots WHERE id=?", bindings: [.uuid(id)]).first,
              var snapshot = snapshotHeader(row) else { return nil }
        let repoRows = try database.query("SELECT * FROM review_snapshot_repositories WHERE snapshot_id=?", bindings: [.uuid(id)])
        snapshot.repositories = try repoRows.compactMap { repoRow in
            guard let repositoryID = repoRow.uuid("repository_id") else { return nil }
            let fileRows = try database.query("SELECT * FROM review_snapshot_files WHERE snapshot_id=? AND repository_id=? ORDER BY path", bindings: [.uuid(id), .uuid(repositoryID)])
            let files = try fileRows.compactMap { fileRow -> SnapshotFile? in
                guard let path = fileRow.text("path"),
                      let statusRaw = fileRow.text("status"), let status = FileStatus(rawValue: statusRaw),
                      let oldHash = fileRow.text("old_blob_hash"),
                      let newHash = fileRow.text("new_blob_hash"),
                      let patchHash = fileRow.text("patch_blob_hash"),
                      let fingerprint = fileRow.text("fingerprint") else { return nil }
                return SnapshotFile(path: path, status: status, oldPath: fileRow.text("old_path"), oldContent: try loadBlob(hash: oldHash), newContent: try loadBlob(hash: newHash), patch: try loadBlob(hash: patchHash), fingerprint: fingerprint)
            }
            return ReviewSnapshotRepository(repositoryID: repositoryID, headOID: repoRow.text("head_oid"), branch: repoRow.text("branch") ?? "", files: files)
        }
        return snapshot
    }

    public func saveAnnotation(_ annotation: ReviewAnnotation) throws {
        try database.execute(
            "INSERT INTO review_annotations(id,workspace_id,activity_session_id,review_session_id,repository_id,snapshot_id,kind,file_path,side,start_line,end_line,anchor_fingerprint,selected_code,surrounding_context,user_text,response,created_at,resolved_at,is_outdated) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            bindings: [.uuid(annotation.id), .uuid(annotation.workspaceID), .uuid(annotation.activitySessionID), .uuid(annotation.reviewSessionID), .uuid(annotation.repositoryID), .uuid(annotation.snapshotID), .text(annotation.kind.rawValue), .text(annotation.filePath), .text(annotation.side.rawValue), .integer(Int64(annotation.startLine)), .integer(Int64(annotation.endLine)), .text(annotation.anchorFingerprint), .text(annotation.selectedCode), .text(annotation.context), .text(annotation.userText), annotation.response.map(SQLiteValue.text) ?? .null, .date(annotation.createdAt), annotation.resolvedAt.map(SQLiteValue.date) ?? .null, .integer(annotation.isOutdated ? 1 : 0)]
        )
    }

    public func annotations(workspaceID: UUID) throws -> [ReviewAnnotation] {
        try database.query("SELECT * FROM review_annotations WHERE workspace_id=? ORDER BY created_at", bindings: [.uuid(workspaceID)]).compactMap { row in
            guard let id = row.uuid("id"), let activityID = row.uuid("activity_session_id"), let reviewID = row.uuid("review_session_id"), let repositoryID = row.uuid("repository_id"), let snapshotID = row.uuid("snapshot_id"), let kindRaw = row.text("kind"), let kind = AnnotationKind(rawValue: kindRaw), let filePath = row.text("file_path"), let sideRaw = row.text("side"), let side = DiffSide(rawValue: sideRaw), let fingerprint = row.text("anchor_fingerprint"), let code = row.text("selected_code"), let context = row.text("surrounding_context"), let userText = row.text("user_text") else { return nil }
            return ReviewAnnotation(id: id, workspaceID: workspaceID, activitySessionID: activityID, reviewSessionID: reviewID, repositoryID: repositoryID, snapshotID: snapshotID, kind: kind, filePath: filePath, side: side, startLine: row.integer("start_line"), endLine: row.integer("end_line"), anchorFingerprint: fingerprint, selectedCode: code, context: context, userText: userText, response: row.text("response"), createdAt: row.date("created_at"), resolvedAt: row.optionalDate("resolved_at"), isOutdated: row.integer("is_outdated") != 0)
        }
    }

    public func updateAnnotationText(id: UUID, text: String) throws {
        try database.execute(
            "UPDATE review_annotations SET user_text=? WHERE id=?",
            bindings: [.text(text), .uuid(id)]
        )
    }

    public func deleteAnnotation(id: UUID) throws {
        try database.execute("DELETE FROM review_annotations WHERE id=?", bindings: [.uuid(id)])
    }

    public func markAnnotationOutdated(id: UUID, isOutdated: Bool) throws {
        try database.execute("UPDATE review_annotations SET is_outdated=? WHERE id=?", bindings: [.integer(isOutdated ? 1 : 0), .uuid(id)])
    }

    public func saveAssistantThread(_ thread: AssistantThreadRecord) throws {
        try database.execute("INSERT INTO assistant_threads(id,annotation_id,provider,provider_session_id,model,created_at) VALUES(?,?,?,?,?,?)", bindings: [.uuid(thread.id), .uuid(thread.annotationID), .text(thread.provider.rawValue), thread.providerSessionID.map(SQLiteValue.text) ?? .null, thread.model.map(SQLiteValue.text) ?? .null, .date(thread.createdAt)])
    }

    public func saveAssistantMessage(_ message: AssistantMessageRecord) throws {
        try database.execute("INSERT OR REPLACE INTO assistant_messages(id,thread_id,role,content,is_streaming,error_code,created_at) VALUES(?,?,?,?,?,?,?)", bindings: [.uuid(message.id), .uuid(message.threadID), .text(message.role.rawValue), .text(message.content), .integer(message.isStreaming ? 1 : 0), message.errorCode.map(SQLiteValue.text) ?? .null, .date(message.createdAt)])
    }

    public func saveNotification(_ notification: NotificationRecord) throws {
        try database.execute("INSERT INTO notifications(id,workspace_id,tab_id,title,body,created_at,read_at) VALUES(?,?,?,?,?,?,?)", bindings: [.uuid(notification.id), .uuid(notification.workspaceID), notification.tabID.map(SQLiteValue.uuid) ?? .null, .text(notification.title), .text(notification.body), .date(notification.createdAt), notification.readAt.map(SQLiteValue.date) ?? .null])
    }

    public func setSettingData(_ value: Data, forKey key: String) throws {
        try database.execute("INSERT INTO settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at", bindings: [.text(key), .blob(value), .date(Date())])
    }

    public func settingData(forKey key: String) throws -> Data? {
        try database.query("SELECT value FROM settings WHERE key=?", bindings: [.text(key)]).first?["value"].data
    }

    public func removeSetting(forKey key: String) throws {
        try database.execute("DELETE FROM settings WHERE key=?", bindings: [.text(key)])
    }

    private func loadRepositories(workspaceID: UUID) throws -> [WorkspaceRepositoryRecord] {
        try database.query("SELECT * FROM workspace_repositories WHERE workspace_id=? ORDER BY sort_index", bindings: [.uuid(workspaceID)]).compactMap { row in
            guard let id = row.uuid("id"), let sourceID = row.uuid("source_id"), let name = row.text("name"), let path = row.text("worktree_path"), let branch = row.text("branch") else { return nil }
            return WorkspaceRepositoryRecord(id: id, workspaceID: workspaceID, sourceID: sourceID, name: name, worktreePath: URL(fileURLWithPath: path, isDirectory: true), branch: branch, baseBranch: row.text("base_branch"), sortIndex: row.integer("sort_index"))
        }
    }

    private func loadTabs(workspaceID: UUID) throws -> [TabRecord] {
        try database.query("SELECT * FROM tabs WHERE workspace_id=? ORDER BY sort_index", bindings: [.uuid(workspaceID)]).compactMap { row in
            guard let id = row.uuid("id"), let kindRaw = row.text("kind"), let kind = TabKind(rawValue: kindRaw), let title = row.text("title") else { return nil }
            return TabRecord(id: id, workspaceID: workspaceID, kind: kind, title: title, sortIndex: row.integer("sort_index"), workingDirectory: row.text("working_directory").map { URL(fileURLWithPath: $0, isDirectory: true) }, repositoryID: row.uuid("repository_id"), createdAt: row.date("created_at"))
        }
    }

    private func loadLayout(workspaceID: UUID) throws -> WorkspaceLayoutRecord {
        guard let row = try database.query("SELECT * FROM workspace_layouts WHERE workspace_id=?", bindings: [.uuid(workspaceID)]).first else { return WorkspaceLayoutRecord(workspaceID: workspaceID) }
        return WorkspaceLayoutRecord(workspaceID: workspaceID, primaryTabID: row.uuid("primary_tab_id"), companionTabID: row.uuid("companion_tab_id"), focusedTabID: row.uuid("focused_tab_id"), splitRatio: row.double("split_ratio"))
    }

    private func insertTab(_ tab: TabRecord) throws {
        try database.execute("INSERT INTO tabs(id,workspace_id,kind,title,sort_index,repository_id,working_directory,created_at) VALUES(?,?,?,?,?,?,?,?)", bindings: [.uuid(tab.id), .uuid(tab.workspaceID), .text(tab.kind.rawValue), .text(tab.title), .integer(Int64(tab.sortIndex)), tab.repositoryID.map(SQLiteValue.uuid) ?? .null, tab.workingDirectory.map { .text($0.path) } ?? .null, .date(tab.createdAt)])
    }

    private func insertTerminal(_ terminal: TerminalSessionRecord) throws {
        let kind: String
        let lines: SQLiteValue
        switch terminal.scrollback {
        case .disabled: kind = "disabled"; lines = .null
        case .unlimited: kind = "unlimited"; lines = .null
        case .limited(let count): kind = "limited"; lines = .integer(Int64(count))
        }
        try database.execute("INSERT INTO terminal_sessions(tab_id,working_directory,startup_input,resume_provider,resume_identifier,scrollback_kind,scrollback_lines) VALUES(?,?,?,?,?,?,?)", bindings: [.uuid(terminal.tabID), .text(terminal.workingDirectory.path), terminal.startupInput.map(SQLiteValue.text) ?? .null, terminal.resumeProvider.map(SQLiteValue.text) ?? .null, terminal.resumeIdentifier.map(SQLiteValue.text) ?? .null, .text(kind), lines])
    }

    private func insertLayout(_ layout: WorkspaceLayoutRecord) throws {
        try database.execute("INSERT INTO workspace_layouts(workspace_id,primary_tab_id,companion_tab_id,focused_tab_id,split_ratio) VALUES(?,?,?,?,?)", bindings: [.uuid(layout.workspaceID), layout.primaryTabID.map(SQLiteValue.uuid) ?? .null, layout.companionTabID.map(SQLiteValue.uuid) ?? .null, layout.focusedTabID.map(SQLiteValue.uuid) ?? .null, .real(layout.splitRatio)])
    }

    private func persistSnapshot(_ snapshot: ReviewSnapshotRecord) throws -> ReviewSnapshotRecord {
        if let existingID = try database.query("SELECT id FROM review_snapshots WHERE workspace_id=? AND fingerprint=?", bindings: [.uuid(snapshot.workspaceID), .text(snapshot.fingerprint)]).first?.uuid("id"), let existing = try loadSnapshot(id: existingID) { return existing }
        try database.execute("INSERT INTO review_snapshots(id,workspace_id,activity_session_id,review_session_id,fingerprint,reason,created_at) VALUES(?,?,?,?,?,?,?)", bindings: [.uuid(snapshot.id), .uuid(snapshot.workspaceID), .uuid(snapshot.activitySessionID), snapshot.reviewSessionID.map(SQLiteValue.uuid) ?? .null, .text(snapshot.fingerprint), .text(snapshot.reason), .date(snapshot.createdAt)])
        for repository in snapshot.repositories {
            try database.execute("INSERT INTO review_snapshot_repositories(snapshot_id,repository_id,head_oid,branch) VALUES(?,?,?,?)", bindings: [.uuid(snapshot.id), .uuid(repository.repositoryID), repository.headOID.map(SQLiteValue.text) ?? .null, .text(repository.branch)])
            for file in repository.files {
                let oldHash = try storeBlob(file.oldContent)
                let newHash = try storeBlob(file.newContent)
                let patchHash = try storeBlob(file.patch)
                try database.execute("INSERT INTO review_snapshot_files(snapshot_id,repository_id,path,status,old_path,old_blob_hash,new_blob_hash,patch_blob_hash,fingerprint) VALUES(?,?,?,?,?,?,?,?,?)", bindings: [.uuid(snapshot.id), .uuid(repository.repositoryID), .text(file.path), .text(file.status.rawValue), file.oldPath.map(SQLiteValue.text) ?? .null, .text(oldHash), .text(newHash), .text(patchHash), .text(file.fingerprint)])
            }
        }
        return snapshot
    }

    private func snapshotHeader(_ row: SQLiteRow) -> ReviewSnapshotRecord? {
        guard let id = row.uuid("id"), let workspaceID = row.uuid("workspace_id"), let activityID = row.uuid("activity_session_id"), let fingerprint = row.text("fingerprint"), let reason = row.text("reason") else { return nil }
        return ReviewSnapshotRecord(id: id, workspaceID: workspaceID, activitySessionID: activityID, reviewSessionID: row.uuid("review_session_id"), fingerprint: fingerprint, reason: reason, createdAt: row.date("created_at"), repositories: [])
    }

    private func reviewSession(from row: SQLiteRow) -> ReviewSessionRecord? {
        guard let id = row.uuid("id"), let workspaceID = row.uuid("workspace_id"), let activityID = row.uuid("activity_session_id") else { return nil }
        return ReviewSessionRecord(id: id, workspaceID: workspaceID, activitySessionID: activityID, startedAt: row.date("started_at"), completedAt: row.optionalDate("completed_at"), finalSnapshotID: row.uuid("final_snapshot_id"))
    }

    private func storeBlob(_ string: String) throws -> String {
        let source = Data(string.utf8)
        let hash = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
        if try database.scalarInt("SELECT COUNT(*) AS value FROM snapshot_blobs WHERE content_hash=?", bindings: [.text(hash)]) ?? 0 > 0 { return hash }
        let compressed = Self.compress(source) ?? source
        let codec = compressed.count < source.count ? "zlib" : "none"
        try database.execute("INSERT INTO snapshot_blobs(content_hash,codec,original_size,content) VALUES(?,?,?,?)", bindings: [.text(hash), .text(codec), .integer(Int64(source.count)), .blob(codec == "zlib" ? compressed : source)])
        return hash
    }

    private func loadBlob(hash: String) throws -> String {
        guard let row = try database.query("SELECT * FROM snapshot_blobs WHERE content_hash=?", bindings: [.text(hash)]).first,
              let data = row["content"].data else { return "" }
        let decoded = row.text("codec") == "zlib" ? Self.decompress(data, size: row.integer("original_size")) ?? data : data
        return String(decoding: decoded, as: UTF8.self)
    }

    private static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = max(64, data.count + data.count / 8 + 64)
        var output = Data(count: capacity)
        let count = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, capacity, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count > 0 else { return nil }
        output.count = count
        return output
    }

    private static func decompress(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let count = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, size, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard count == size else { return nil }
        return output
    }

    private func clampedRatio(_ ratio: Double) -> Double { min(0.8, max(0.2, ratio)) }

    public static func canonicalRemoteURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@"), let separator = value.firstIndex(of: ":") {
            let host = value[value.index(value.startIndex, offsetBy: 4)..<separator].lowercased()
            let path = value[value.index(after: separator)...]
            value = "ssh://git@\(host)/\(path)"
        } else if var components = URLComponents(string: value) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            value = components.string ?? value
        }
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value
    }
}

public extension StateRepository {
    func setSetting<T: Encodable & Sendable>(_ value: T, forKey key: String) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try await setSettingData(encoder.encode(value), forKey: key)
    }

    func setting<T: Decodable & Sendable>(_ type: T.Type, forKey key: String) async throws -> T? {
        guard let data = try await settingData(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(type, from: data)
    }
}

private extension SQLiteValue {
    static func uuid(_ value: UUID) -> SQLiteValue { .text(value.uuidString) }
    static func date(_ value: Date) -> SQLiteValue { .real(value.timeIntervalSince1970) }
}

private extension SQLiteRow {
    func text(_ column: String) -> String? { self[column].string }
    func integer(_ column: String) -> Int { Int(self[column].int ?? 0) }
    func double(_ column: String) -> Double { self[column].double ?? 0 }
    func uuid(_ column: String) -> UUID? { text(column).flatMap(UUID.init(uuidString:)) }
    func date(_ column: String) -> Date { Date(timeIntervalSince1970: self[column].double ?? 0) }
    func optionalDate(_ column: String) -> Date? { self[column].double.map(Date.init(timeIntervalSince1970:)) }
}
