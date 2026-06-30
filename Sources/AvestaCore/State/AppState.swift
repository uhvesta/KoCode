import Foundation
import Observation

@Observable
@MainActor
public final class AppState {
    public var workspaces: [Workspace]
    public var activeWorkspaceID: UUID?
    public var globalBoard: BoardStore
    public var config: AppConfig
    public var cachedRepos: [CachedRepo]
    public var notificationBadges: [UUID: Int]
    public var notificationBanners: [InAppNotificationBanner]
    public var isBoardVisible: Bool {
        didSet { persistSession() }
    }
    public var lastErrorMessage: String?
    public let gitService: GitService
    public let sessionStore: AppSessionStore

    public init(
        workspaces: [Workspace] = [],
        activeWorkspaceID: UUID? = nil,
        globalBoard: BoardStore? = nil,
        config: AppConfig = .default,
        cachedRepos: [CachedRepo] = [],
        notificationBadges: [UUID: Int] = [:],
        notificationBanners: [InAppNotificationBanner] = [],
        isBoardVisible: Bool = false,
        gitService: GitService? = nil,
        sessionStore: AppSessionStore = AppSessionStore()
    ) {
        self.config = config
        self.notificationBadges = notificationBadges
        self.notificationBanners = notificationBanners
        self.lastErrorMessage = nil
        self.gitService = gitService ?? GitService(cacheRoot: config.cacheRoot)
        self.sessionStore = sessionStore

        if workspaces.isEmpty,
           activeWorkspaceID == nil,
           cachedRepos.isEmpty,
           globalBoard == nil,
           let snapshot = try? sessionStore.load() {
            self.workspaces = Self.workspaces(from: snapshot)
            self.activeWorkspaceID = snapshot.activeWorkspaceID
            self.globalBoard = BoardStore(items: snapshot.globalBoardItems)
            self.cachedRepos = snapshot.cachedRepos
            self.isBoardVisible = snapshot.isBoardVisible
        } else {
            self.workspaces = workspaces
            self.activeWorkspaceID = activeWorkspaceID
            self.globalBoard = globalBoard ?? BoardStore()
            self.cachedRepos = cachedRepos
            self.isBoardVisible = isBoardVisible
        }
    }

    public var activeWorkspace: Workspace? {
        get {
            guard let activeWorkspaceID else { return workspaces.first }
            return workspaces.first { $0.id == activeWorkspaceID }
        }
        set {
            activeWorkspaceID = newValue?.id
            persistSession()
        }
    }

    public func createWorkspace(name: String) {
        let path = config.workspacesRoot.appending(path: name, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        let workspace = Workspace(name: name, path: path)
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        persistSession()
    }

    public func createWorkspace(
        name: String,
        cachedRepo: CachedRepo?,
        remoteURL: String?,
        branch: String
    ) async {
        do {
            let workspacePath = config.workspacesRoot.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: workspacePath, withIntermediateDirectories: true)

            var repos: [WorktreeRef] = []
            if let repo = cachedRepo {
                let worktreePath = workspacePath.appending(path: repo.name, directoryHint: .isDirectory)
                try await gitService.createWorktree(bareRepo: repo.bareClonePath, branch: branch, destination: worktreePath)
                repos.append(WorktreeRef(repoName: repo.name, bareRepoPath: repo.bareClonePath, worktreePath: worktreePath, branch: branch, remoteURL: repo.remoteURL))
            } else if let remoteURL, !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let repoName = Self.repositoryName(from: remoteURL)
                let bareRepo = try await gitService.ensureBareClone(remoteURL: remoteURL, name: repoName)
                let worktreePath = workspacePath.appending(path: repoName, directoryHint: .isDirectory)
                try await gitService.createWorktree(bareRepo: bareRepo, branch: branch, destination: worktreePath)
                let cachedRepo = CachedRepo(name: repoName, bareClonePath: bareRepo, remoteURL: remoteURL, lastFetched: Date())
                cachedRepos.append(cachedRepo)
                repos.append(WorktreeRef(repoName: repoName, bareRepoPath: bareRepo, worktreePath: worktreePath, branch: branch, remoteURL: remoteURL))
            }

            let workspace = Workspace(name: name, path: workspacePath, repos: repos)
            workspaces.append(workspace)
            activeWorkspaceID = workspace.id
            lastErrorMessage = nil
            persistSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func addRepository(
        to workspaceID: UUID,
        cachedRepo: CachedRepo?,
        remoteURL: String?,
        branch: String
    ) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }

        do {
            try FileManager.default.createDirectory(at: workspace.path, withIntermediateDirectories: true)

            let repoName: String
            let bareRepo: URL
            let origin: String

            if let cachedRepo {
                repoName = cachedRepo.name
                bareRepo = cachedRepo.bareClonePath
                origin = cachedRepo.remoteURL
            } else if let remoteURL, !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                repoName = Self.repositoryName(from: remoteURL)
                bareRepo = try await gitService.ensureBareClone(remoteURL: remoteURL, name: repoName)
                origin = remoteURL

                if !cachedRepos.contains(where: { $0.remoteURL == remoteURL }) {
                    cachedRepos.append(CachedRepo(name: repoName, bareClonePath: bareRepo, remoteURL: remoteURL, lastFetched: Date()))
                }
            } else {
                lastErrorMessage = "Choose a cached repository or enter a remote URL."
                return
            }

            let worktreePath = availableWorktreePath(for: repoName, in: workspace.path)
            try await gitService.createWorktree(bareRepo: bareRepo, branch: branch, destination: worktreePath)
            workspace.repos.append(WorktreeRef(repoName: repoName, bareRepoPath: bareRepo, worktreePath: worktreePath, branch: branch, remoteURL: origin))
            lastErrorMessage = nil
            persistSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func deleteWorkspace(id: UUID) async {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = workspaces[index]

        do {
            for repo in workspace.repos {
                try await gitService.removeWorktree(bareRepo: repo.bareRepoPath, worktreePath: repo.worktreePath)
            }
            try? FileManager.default.removeItem(at: workspace.path)
            workspaces.remove(at: index)
            if activeWorkspaceID == id {
                activeWorkspaceID = workspaces.first?.id
            }
            lastErrorMessage = nil
            persistSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func closeWorkspace(id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces.remove(at: index)
        if activeWorkspaceID == id {
            activeWorkspaceID = workspaces.first?.id
        }
        persistSession()
    }

    public func incrementBadge(for tabID: UUID) {
        notificationBadges[tabID, default: 0] += 1
    }

    public func notifyInApp(title: String, body: String, tabID: UUID) {
        notificationBanners.insert(InAppNotificationBanner(title: title, body: body, tabID: tabID), at: 0)
        if notificationBanners.count > 5 {
            notificationBanners.removeLast(notificationBanners.count - 5)
        }
    }

    public func clearBadge(for tabID: UUID) {
        notificationBadges[tabID] = nil
    }

    public func pasteMostRecentBoardItemToActiveTerminal() {
        guard
            let item = activeWorkspace?.board.paste() ?? globalBoard.paste(),
            let terminal = activeWorkspace?.activeTab as? TerminalTabModel
        else { return }

        terminal.pendingPaste = item.content
    }

    public func pasteBoardItemToActiveTerminal(_ item: BoardItem) {
        guard let terminal = activeWorkspace?.activeTab as? TerminalTabModel else { return }
        terminal.pendingPaste = item.content
    }

    public func sendActiveTerminalOutputToBoard() {
        guard let terminal = activeWorkspace?.activeTab as? TerminalTabModel else { return }
        activeWorkspace?.board.send(terminal.outputBuffer, source: "Terminal: \(terminal.title)")
        persistSession()
    }

    public func selectTab(at index: Int) {
        guard let workspace = activeWorkspace, workspace.tabs.indices.contains(index) else { return }
        let tabID = workspace.tabs[index].id
        workspace.activeTabID = tabID
        clearBadge(for: tabID)
        persistSession()
    }

    public func selectWorkspace(id: UUID?) {
        activeWorkspaceID = id
        persistSession()
    }

    public func addTerminalTab() {
        guard let workspace = activeWorkspace else { return }
        workspace.addTerminalTab()
        persistSession()
    }

    public func addCodeReviewTab() {
        guard let workspace = activeWorkspace else { return }
        workspace.addCodeReviewTab()
        persistSession()
    }

    public func closeActiveTab() {
        guard let workspace = activeWorkspace, let tabID = workspace.activeTab?.id else { return }
        workspace.closeTab(id: tabID)
        persistSession()
    }

    public func closeActiveTabOrCloseEmptyWorkspace() async {
        guard let workspace = activeWorkspace else { return }
        if let tabID = workspace.activeTab?.id {
            workspace.closeTab(id: tabID)
            persistSession()
        } else {
            closeWorkspace(id: workspace.id)
        }
    }

    public func closeTab(id: UUID) {
        activeWorkspace?.closeTab(id: id)
        persistSession()
    }

    public func updateCodeReviewSession(_ session: CodeReviewSession?, for tabID: UUID) {
        guard let tab = tab(with: tabID) as? CodeReviewTabModel else { return }
        tab.session = session
        persistSession()
    }

    public func persistSession() {
        do {
            try sessionStore.save(sessionSnapshot())
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func sessionSnapshot() -> AppSessionSnapshot {
        AppSessionSnapshot(
            workspaces: workspaces.map(Self.snapshot(from:)),
            activeWorkspaceID: activeWorkspaceID,
            cachedRepos: cachedRepos,
            globalBoardItems: globalBoard.items,
            isBoardVisible: isBoardVisible
        )
    }

    private func tab(with id: UUID) -> (any WorkspaceTab)? {
        for workspace in workspaces {
            if let tab = workspace.tabs.first(where: { $0.id == id }) {
                return tab
            }
        }
        return nil
    }

    private static func repositoryName(from remoteURL: String) -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = trimmed.split(separator: "/").last.map(String.init) ?? "repo"
        return last.replacingOccurrences(of: ".git", with: "")
    }

    private func availableWorktreePath(for repoName: String, in workspacePath: URL) -> URL {
        var candidate = workspacePath.appending(path: repoName, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = workspacePath.appending(path: "\(repoName)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
    }

    private static func snapshot(from workspace: Workspace) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: workspace.id,
            name: workspace.name,
            path: workspace.path,
            repos: workspace.repos,
            tabs: workspace.tabs.compactMap(snapshot(from:)),
            activeTabID: workspace.activeTabID,
            boardItems: workspace.board.items
        )
    }

    private static func snapshot(from tab: any WorkspaceTab) -> TabSnapshot? {
        switch tab.kind {
        case .terminal:
            guard let terminal = tab as? TerminalTabModel else { return nil }
            return .terminal(TerminalTabSnapshot(
                id: terminal.id,
                title: terminal.title,
                workingDirectory: terminal.workingDirectory,
                resume: terminal.resume
            ))
        case .codeReview:
            guard let codeReview = tab as? CodeReviewTabModel else { return nil }
            return .codeReview(CodeReviewTabSnapshot(
                id: codeReview.id,
                title: codeReview.title,
                session: codeReview.session.map(snapshot(from:))
            ))
        }
    }

    private static func snapshot(from session: CodeReviewSession) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            id: session.id,
            diffSpec: session.diffSpec,
            repoPath: session.repoPath,
            files: session.files,
            activeFileIndex: session.activeFileIndex,
            comments: session.comments
        )
    }

    private static func workspaces(from snapshot: AppSessionSnapshot) -> [Workspace] {
        snapshot.workspaces.map { workspace in
            Workspace(
                id: workspace.id,
                name: workspace.name,
                path: workspace.path,
                repos: workspace.repos,
                tabs: workspace.tabs.map(tab(from:)),
                activeTabID: workspace.activeTabID,
                board: BoardStore(items: workspace.boardItems),
                createsDefaultTab: false
            )
        }
    }

    private static func tab(from snapshot: TabSnapshot) -> any WorkspaceTab {
        switch snapshot {
        case .terminal(let terminal):
            return TerminalTabModel(
                id: terminal.id,
                title: terminal.title,
                workingDirectory: terminal.workingDirectory,
                resume: terminal.resume
            )
        case .codeReview(let codeReview):
            return CodeReviewTabModel(
                id: codeReview.id,
                title: codeReview.title,
                session: codeReview.session.map(session(from:))
            )
        }
    }

    private static func session(from snapshot: CodeReviewSessionSnapshot) -> CodeReviewSession {
        CodeReviewSession(
            id: snapshot.id,
            diffSpec: snapshot.diffSpec,
            repoPath: snapshot.repoPath,
            files: snapshot.files,
            activeFileIndex: snapshot.activeFileIndex,
            comments: snapshot.comments
        )
    }
}

public struct InAppNotificationBanner: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let tabID: UUID
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, body: String, tabID: UUID, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.tabID = tabID
        self.createdAt = createdAt
    }
}
