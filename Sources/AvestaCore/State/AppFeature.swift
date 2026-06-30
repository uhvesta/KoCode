import ComposableArchitecture
import Foundation

public enum AppFeatureEffectError: Error, Equatable, Sendable {
    case message(String)

    public var localizedDescription: String {
        switch self {
        case .message(let message):
            return message
        }
    }
}

public enum AppFeatureEffectStatus: Equatable, Sendable {
    case success
    case failure(String)
}

public enum CodeReviewDiffLoadResult: Equatable, Sendable {
    case success([FileDiff])
    case failure(String)
}

@Reducer
public struct AppFeature: Sendable {
    private let config: AppConfig
    private let gitService: GitService
    private let sessionStore: AppSessionStore
    private let fileManager: FileManager

    public init(
        config: AppConfig = .default,
        gitService: GitService? = nil,
        sessionStore: AppSessionStore = AppSessionStore(),
        fileManager: FileManager = .default
    ) {
        self.config = config
        self.gitService = gitService ?? GitService(cacheRoot: config.cacheRoot, fileManager: fileManager)
        self.sessionStore = sessionStore
        self.fileManager = fileManager
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var workspaces: [WorkspaceState]
        public var activeWorkspaceID: UUID?
        public var globalBoardItems: [BoardItem]
        public var cachedRepos: [CachedRepo]
        public var notificationBadges: [UUID: Int]
        public var notificationBanners: [InAppNotificationBanner]
        public var isBoardVisible: Bool
        public var lastErrorMessage: String?
        public var newWorkspaceForm: NewWorkspaceFeature.State
        public var addRepositoryForm: AddRepositoryFeature.State
        public var settings: SettingsFeature.State
        public var lastPersistenceSnapshot: AppSessionSnapshot?

        public init(
            workspaces: [WorkspaceState] = [],
            activeWorkspaceID: UUID? = nil,
            globalBoardItems: [BoardItem] = [],
            cachedRepos: [CachedRepo] = [],
            notificationBadges: [UUID: Int] = [:],
            notificationBanners: [InAppNotificationBanner] = [],
            isBoardVisible: Bool = false,
            lastErrorMessage: String? = nil,
            newWorkspaceForm: NewWorkspaceFeature.State = NewWorkspaceFeature.State(),
            addRepositoryForm: AddRepositoryFeature.State = AddRepositoryFeature.State(),
            settings: SettingsFeature.State = SettingsFeature.State(config: .default),
            lastPersistenceSnapshot: AppSessionSnapshot? = nil
        ) {
            self.workspaces = workspaces
            self.activeWorkspaceID = activeWorkspaceID
            self.globalBoardItems = globalBoardItems
            self.cachedRepos = cachedRepos
            self.notificationBadges = notificationBadges
            self.notificationBanners = notificationBanners
            self.isBoardVisible = isBoardVisible
            self.lastErrorMessage = lastErrorMessage
            self.newWorkspaceForm = newWorkspaceForm
            self.addRepositoryForm = addRepositoryForm
            self.settings = settings
            self.lastPersistenceSnapshot = lastPersistenceSnapshot
        }

        public var activeWorkspace: WorkspaceState? {
            guard let activeWorkspaceID else { return workspaces.first }
            return workspaces.first { $0.id == activeWorkspaceID }
        }

        public var activeWorkspaceIndex: Int? {
            guard let activeWorkspaceID else { return workspaces.indices.first }
            return workspaces.firstIndex { $0.id == activeWorkspaceID }
        }

        public static func restored(
            config: AppConfig = .default,
            sessionStore: AppSessionStore = AppSessionStore()
        ) -> Self {
            guard let snapshot = try? sessionStore.load() else {
                return Self(settings: SettingsFeature.State(config: config))
            }
            return Self(
                workspaces: snapshot.workspaces.map(WorkspaceState.init(snapshot:)),
                activeWorkspaceID: snapshot.activeWorkspaceID,
                globalBoardItems: snapshot.globalBoardItems,
                cachedRepos: snapshot.cachedRepos,
                isBoardVisible: snapshot.isBoardVisible,
                settings: SettingsFeature.State(config: config),
                lastPersistenceSnapshot: snapshot
            )
        }

        public func sessionSnapshot() -> AppSessionSnapshot {
            AppSessionSnapshot(
                workspaces: workspaces.map(\.snapshot),
                activeWorkspaceID: activeWorkspaceID,
                cachedRepos: cachedRepos,
                globalBoardItems: globalBoardItems,
                isBoardVisible: isBoardVisible
            )
        }
    }

    public struct WorkspaceState: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var path: URL
        public var repos: [WorktreeRef]
        public var tabs: [TabState]
        public var activeTabID: UUID?
        public var boardItems: [BoardItem]

        public init(
            id: UUID = UUID(),
            name: String,
            path: URL,
            repos: [WorktreeRef] = [],
            tabs: [TabState] = [],
            activeTabID: UUID? = nil,
            boardItems: [BoardItem] = []
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.repos = repos
            self.tabs = tabs
            self.activeTabID = activeTabID ?? tabs.first?.id
            self.boardItems = boardItems
        }

        public init(snapshot: WorkspaceSnapshot) {
            self.init(
                id: snapshot.id,
                name: snapshot.name,
                path: snapshot.path,
                repos: snapshot.repos,
                tabs: snapshot.tabs.map(TabState.init(snapshot:)),
                activeTabID: snapshot.activeTabID,
                boardItems: snapshot.boardItems
            )
        }

        public var activeTab: TabState? {
            guard let activeTabID else { return tabs.first }
            return tabs.first { $0.id == activeTabID }
        }

        public var activeTabIndex: Int? {
            guard let activeTabID else { return tabs.indices.first }
            return tabs.firstIndex { $0.id == activeTabID }
        }

        public var snapshot: WorkspaceSnapshot {
            WorkspaceSnapshot(
                id: id,
                name: name,
                path: path,
                repos: repos,
                tabs: tabs.map(\.snapshot),
                activeTabID: activeTabID,
                boardItems: boardItems
            )
        }
    }

    public enum TabState: Equatable, Identifiable, Sendable {
        case terminal(TerminalTabState)
        case codeReview(CodeReviewTabState)

        public var id: UUID {
            switch self {
            case .terminal(let tab): return tab.id
            case .codeReview(let tab): return tab.id
            }
        }

        public var title: String {
            switch self {
            case .terminal(let tab): return tab.title
            case .codeReview(let tab): return tab.title
            }
        }

        public var kind: TabKind {
            switch self {
            case .terminal: return .terminal
            case .codeReview: return .codeReview
            }
        }

        public init(snapshot: TabSnapshot) {
            switch snapshot {
            case .terminal(let terminal):
                self = .terminal(TerminalTabState(snapshot: terminal))
            case .codeReview(let codeReview):
                self = .codeReview(CodeReviewTabState(snapshot: codeReview))
            }
        }

        public var snapshot: TabSnapshot {
            switch self {
            case .terminal(let terminal):
                return .terminal(TerminalTabSnapshot(
                    id: terminal.id,
                    title: terminal.title,
                    workingDirectory: terminal.workingDirectory,
                    resume: terminal.resume
                ))
            case .codeReview(let review):
                return .codeReview(CodeReviewTabSnapshot(
                    id: review.id,
                    title: review.title,
                    session: review.flow.map {
                        CodeReviewSessionSnapshot(
                            id: $0.session.id,
                            diffSpec: $0.session.diffSpec,
                            repoPath: $0.session.repoPath,
                            files: $0.session.files,
                            activeFileIndex: $0.session.activeFileIndex,
                            comments: $0.session.comments
                        )
                    }
                ))
            }
        }
    }

    public struct TerminalTabState: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var workingDirectory: URL
        public var outputBuffer: String
        public var pendingPaste: String?
        public var resume: TerminalResumeSnapshot?

        public init(
            id: UUID = UUID(),
            title: String = "Terminal",
            workingDirectory: URL,
            outputBuffer: String = "",
            pendingPaste: String? = nil,
            resume: TerminalResumeSnapshot? = nil
        ) {
            self.id = id
            self.title = title
            self.workingDirectory = workingDirectory
            self.outputBuffer = outputBuffer
            self.pendingPaste = pendingPaste
            self.resume = resume
        }

        public init(snapshot: TerminalTabSnapshot) {
            self.init(
                id: snapshot.id,
                title: snapshot.title,
                workingDirectory: snapshot.workingDirectory,
                resume: snapshot.resume
            )
        }
    }

    public struct CodeReviewTabState: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var flow: CodeReviewFlowFeature.State?

        public init(
            id: UUID = UUID(),
            title: String = "Code Review",
            flow: CodeReviewFlowFeature.State? = nil
        ) {
            self.id = id
            self.title = title
            self.flow = flow
        }

        public init(snapshot: CodeReviewTabSnapshot) {
            self.init(
                id: snapshot.id,
                title: snapshot.title,
                flow: snapshot.session.map {
                    CodeReviewFlowFeature.State(
                        session: CodeReviewFlowFeature.CodeReviewSessionState(
                            id: $0.id,
                            diffSpec: $0.diffSpec,
                            repoPath: $0.repoPath,
                            files: $0.files,
                            activeFileIndex: $0.activeFileIndex,
                            comments: $0.comments
                        )
                    )
                }
            )
        }
    }

    public enum Action: Equatable, Sendable {
        case selectWorkspace(UUID?)
        case toggleBoard
        case selectTab(index: Int)
        case closeActiveTabOrWorkspace
        case addTerminalTab(id: UUID)
        case addCodeReviewTab(id: UUID)
        case closeTab(UUID)
        case sendActiveTerminalOutputToBoard(id: UUID, createdAt: Date)
        case pasteMostRecentBoardItemToActiveTerminal
        case pasteBoardItemToActiveTerminal(UUID)
        case terminalOutput(tabID: UUID, output: String)
        case terminalPasteConsumed(tabID: UUID)
        case incrementBadge(tabID: UUID)
        case clearBadge(tabID: UUID)
        case notifyInApp(id: UUID, title: String, body: String, tabID: UUID, createdAt: Date)
        case codeReview(tabID: UUID, CodeReviewFlowFeature.Action)
        case codeReviewLoadDiff(tabID: UUID, repoID: UUID?, diffSpec: String)
        case codeReviewDiffLoaded(tabID: UUID, repoPath: URL, diffSpec: String, CodeReviewDiffLoadResult)
        case newWorkspace(NewWorkspaceFeature.Action)
        case addRepository(AddRepositoryFeature.Action)
        case settings(SettingsFeature.Action)
        case createWorkspaceResponse(id: UUID, name: String, path: URL, repos: [WorktreeRef], cachedRepo: CachedRepo?, AppFeatureEffectStatus)
        case addRepositoryResponse(workspaceID: UUID, repo: WorktreeRef, cachedRepo: CachedRepo?, AppFeatureEffectStatus)
        case deleteWorkspace(UUID)
        case deleteWorkspaceResponse(UUID, AppFeatureEffectStatus)
        case closeWorkspace(UUID)
        case persistSession
        case sessionPersisted(AppFeatureEffectStatus)
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selectWorkspace(let id):
                state.activeWorkspaceID = id
                return .send(.persistSession)

            case .toggleBoard:
                state.isBoardVisible.toggle()
                return .send(.persistSession)

            case .selectTab(let index):
                guard let workspaceIndex = state.activeWorkspaceIndex,
                      state.workspaces[workspaceIndex].tabs.indices.contains(index)
                else { return .none }
                let tabID = state.workspaces[workspaceIndex].tabs[index].id
                state.workspaces[workspaceIndex].activeTabID = tabID
                state.notificationBadges[tabID] = nil
                return .send(.persistSession)

            case .closeActiveTabOrWorkspace:
                guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                guard let tabID = state.workspaces[workspaceIndex].activeTab?.id else {
                    let workspaceID = state.workspaces[workspaceIndex].id
                    state.workspaces.remove(at: workspaceIndex)
                    if state.activeWorkspaceID == workspaceID {
                        state.activeWorkspaceID = state.workspaces.first?.id
                    }
                    return .send(.persistSession)
                }
                closeTab(tabID, in: &state.workspaces[workspaceIndex])
                return .send(.persistSession)

            case .addTerminalTab(let id):
                guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                let path = state.workspaces[workspaceIndex].path
                let tab = TabState.terminal(TerminalTabState(id: id, workingDirectory: path))
                state.workspaces[workspaceIndex].tabs.append(tab)
                state.workspaces[workspaceIndex].activeTabID = id
                return .send(.persistSession)

            case .addCodeReviewTab(let id):
                guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                let tab = TabState.codeReview(CodeReviewTabState(id: id))
                state.workspaces[workspaceIndex].tabs.append(tab)
                state.workspaces[workspaceIndex].activeTabID = id
                return .send(.persistSession)

            case .closeTab(let id):
                guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                closeTab(id, in: &state.workspaces[workspaceIndex])
                return .send(.persistSession)

            case .sendActiveTerminalOutputToBoard(let id, let createdAt):
                guard let workspaceIndex = state.activeWorkspaceIndex,
                      case .terminal(let terminal)? = state.workspaces[workspaceIndex].activeTab
                else { return .none }
                let trimmed = terminal.outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .none }
                state.workspaces[workspaceIndex].boardItems.insert(
                    BoardItem(id: id, content: trimmed, source: "Terminal: \(terminal.title)", createdAt: createdAt),
                    at: 0
                )
                return .send(.persistSession)

            case .pasteMostRecentBoardItemToActiveTerminal:
                guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                let item = state.workspaces[workspaceIndex].boardItems.first ?? state.globalBoardItems.first
                guard let item else { return .none }
                paste(item.content, intoActiveTerminalIn: &state.workspaces[workspaceIndex])
                return .send(.persistSession)

            case .pasteBoardItemToActiveTerminal(let id):
                guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                let item = state.workspaces[workspaceIndex].boardItems.first { $0.id == id }
                    ?? state.globalBoardItems.first { $0.id == id }
                guard let item else { return .none }
                paste(item.content, intoActiveTerminalIn: &state.workspaces[workspaceIndex])
                return .send(.persistSession)

            case .terminalOutput(let tabID, let output):
                for workspaceIndex in state.workspaces.indices {
                    guard let tabIndex = state.workspaces[workspaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
                          case .terminal(var terminal) = state.workspaces[workspaceIndex].tabs[tabIndex]
                    else { continue }
                    terminal.outputBuffer += output
                    if terminal.outputBuffer.count > 50_000 {
                        terminal.outputBuffer.removeFirst(terminal.outputBuffer.count - 50_000)
                    }
                    state.workspaces[workspaceIndex].tabs[tabIndex] = .terminal(terminal)
                    return .none
                }
                return .none

            case .terminalPasteConsumed(let tabID):
                for workspaceIndex in state.workspaces.indices {
                    guard let tabIndex = state.workspaces[workspaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
                          case .terminal(var terminal) = state.workspaces[workspaceIndex].tabs[tabIndex]
                    else { continue }
                    terminal.pendingPaste = nil
                    state.workspaces[workspaceIndex].tabs[tabIndex] = .terminal(terminal)
                    return .send(.persistSession)
                }
                return .none

            case .incrementBadge(let tabID):
                state.notificationBadges[tabID, default: 0] += 1
                return .none

            case .clearBadge(let tabID):
                state.notificationBadges[tabID] = nil
                return .none

            case let .notifyInApp(id, title, body, tabID, createdAt):
                state.notificationBanners.insert(
                    InAppNotificationBanner(id: id, title: title, body: body, tabID: tabID, createdAt: createdAt),
                    at: 0
                )
                if state.notificationBanners.count > 5 {
                    state.notificationBanners.removeLast(state.notificationBanners.count - 5)
                }
                return .none

            case .codeReview(let tabID, let action):
                for workspaceIndex in state.workspaces.indices {
                    guard let tabIndex = state.workspaces[workspaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
                          case .codeReview(var tab) = state.workspaces[workspaceIndex].tabs[tabIndex],
                          var flow = tab.flow
                    else { continue }
                    _ = CodeReviewFlowFeature().reduce(into: &flow, action: action)
                    tab.flow = flow
                    if case .sendReviewToBoardButtonTapped(let id, let now) = action,
                       let item = flow.boardItems.first(where: { $0.id == id }) {
                        state.workspaces[workspaceIndex].boardItems.insert(
                            BoardItem(id: item.id, content: item.content, source: item.source, createdAt: now),
                            at: 0
                        )
                    }
                    state.workspaces[workspaceIndex].tabs[tabIndex] = .codeReview(tab)
                    return .send(.persistSession)
                }
                return .none

            case let .codeReviewLoadDiff(tabID, repoID, diffSpec):
                guard let workspace = state.activeWorkspace,
                      let repo = repoID.flatMap({ id in workspace.repos.first { $0.id == id } }) ?? workspace.repos.first
                else { return .none }
                let trimmedSpec = diffSpec.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedSpec.isEmpty else { return .none }
                state.lastErrorMessage = nil
                return .run { send in
                    do {
                        let files = try await gitService.diff(repoPath: repo.worktreePath, spec: trimmedSpec)
                        await send(.codeReviewDiffLoaded(tabID: tabID, repoPath: repo.worktreePath, diffSpec: trimmedSpec, .success(files)))
                    } catch {
                        await send(.codeReviewDiffLoaded(tabID: tabID, repoPath: repo.worktreePath, diffSpec: trimmedSpec, .failure(error.localizedDescription)))
                    }
                }

            case let .codeReviewDiffLoaded(tabID, repoPath, diffSpec, result):
                switch result {
                case .success(let files):
                    for workspaceIndex in state.workspaces.indices {
                        guard let tabIndex = state.workspaces[workspaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
                              case .codeReview(var tab) = state.workspaces[workspaceIndex].tabs[tabIndex]
                        else { continue }
                        tab.flow = CodeReviewFlowFeature.State(
                            session: CodeReviewFlowFeature.CodeReviewSessionState(
                                diffSpec: diffSpec,
                                repoPath: repoPath,
                                files: files
                            )
                        )
                        state.workspaces[workspaceIndex].tabs[tabIndex] = .codeReview(tab)
                        state.lastErrorMessage = nil
                        return .send(.persistSession)
                    }
                    return .none
                case .failure(let message):
                    state.lastErrorMessage = message
                    return .none
                }

            case .newWorkspace(let action):
                _ = NewWorkspaceFeature().reduce(into: &state.newWorkspaceForm, action: action)
                switch action {
                case .createButtonTapped(let id):
                    let form = state.newWorkspaceForm
                    guard form.isValid else { return .none }
                    let workspacePath = state.settings.config.workspacesRoot.appending(path: form.sanitizedName, directoryHint: .isDirectory)
                    let cachedRepo = form.selectedCachedRepoID.flatMap { id in state.cachedRepos.first { $0.id == id } }
                    return .run { send in
                        do {
                            try fileManager.createDirectory(at: workspacePath, withIntermediateDirectories: true)
                            var repos: [WorktreeRef] = []
                            var createdCachedRepo: CachedRepo?
                            if let cachedRepo {
                                let worktreePath = workspacePath.appending(path: cachedRepo.name, directoryHint: .isDirectory)
                                try await gitService.createWorktree(bareRepo: cachedRepo.bareClonePath, branch: form.sanitizedBranch, destination: worktreePath)
                                repos.append(WorktreeRef(repoName: cachedRepo.name, bareRepoPath: cachedRepo.bareClonePath, worktreePath: worktreePath, branch: form.sanitizedBranch, remoteURL: cachedRepo.remoteURL))
                            } else if !form.sanitizedRemoteURL.isEmpty {
                                let repoName = Self.repositoryName(from: form.sanitizedRemoteURL)
                                let bareRepo = try await gitService.ensureBareClone(remoteURL: form.sanitizedRemoteURL, name: repoName)
                                let worktreePath = workspacePath.appending(path: repoName, directoryHint: .isDirectory)
                                try await gitService.createWorktree(bareRepo: bareRepo, branch: form.sanitizedBranch, destination: worktreePath)
                                createdCachedRepo = CachedRepo(name: repoName, bareClonePath: bareRepo, remoteURL: form.sanitizedRemoteURL, lastFetched: Date())
                                repos.append(WorktreeRef(repoName: repoName, bareRepoPath: bareRepo, worktreePath: worktreePath, branch: form.sanitizedBranch, remoteURL: form.sanitizedRemoteURL))
                            }
                            await send(.createWorkspaceResponse(id: id, name: form.sanitizedName, path: workspacePath, repos: repos, cachedRepo: createdCachedRepo, .success))
                        } catch {
                            await send(.createWorkspaceResponse(id: id, name: form.sanitizedName, path: workspacePath, repos: [], cachedRepo: nil, .failure(error.localizedDescription)))
                        }
                    }
                default:
                    return .none
                }

            case .addRepository(let action):
                _ = AddRepositoryFeature().reduce(into: &state.addRepositoryForm, action: action)
                switch action {
                case .addButtonTapped:
                    guard let workspaceIndex = state.activeWorkspaceIndex else { return .none }
                    let workspace = state.workspaces[workspaceIndex]
                    let form = state.addRepositoryForm
                    guard form.isValid else { return .none }
                    let cachedRepo = form.selectedCachedRepoID.flatMap { id in state.cachedRepos.first { $0.id == id } }
                    return .run { send in
                        do {
                            try fileManager.createDirectory(at: workspace.path, withIntermediateDirectories: true)
                            let repoName: String
                            let bareRepo: URL
                            let origin: String
                            var createdCachedRepo: CachedRepo?
                            if let cachedRepo {
                                repoName = cachedRepo.name
                                bareRepo = cachedRepo.bareClonePath
                                origin = cachedRepo.remoteURL
                            } else {
                                repoName = Self.repositoryName(from: form.sanitizedRemoteURL)
                                bareRepo = try await gitService.ensureBareClone(remoteURL: form.sanitizedRemoteURL, name: repoName)
                                origin = form.sanitizedRemoteURL
                                createdCachedRepo = CachedRepo(name: repoName, bareClonePath: bareRepo, remoteURL: origin, lastFetched: Date())
                            }
                            let worktreePath = availableWorktreePath(for: repoName, in: workspace.path)
                            try await gitService.createWorktree(bareRepo: bareRepo, branch: form.sanitizedBranch, destination: worktreePath)
                            let repo = WorktreeRef(repoName: repoName, bareRepoPath: bareRepo, worktreePath: worktreePath, branch: form.sanitizedBranch, remoteURL: origin)
                            await send(.addRepositoryResponse(workspaceID: workspace.id, repo: repo, cachedRepo: createdCachedRepo, .success))
                        } catch {
                            let fallback = WorktreeRef(repoName: "repository", bareRepoPath: workspace.path, worktreePath: workspace.path, branch: form.sanitizedBranch, remoteURL: form.sanitizedRemoteURL)
                            await send(.addRepositoryResponse(workspaceID: workspace.id, repo: fallback, cachedRepo: nil, .failure(error.localizedDescription)))
                        }
                    }
                default:
                    return .none
                }

            case .settings(let action):
                _ = SettingsFeature().reduce(into: &state.settings, action: action)
                return .send(.persistSession)

            case let .createWorkspaceResponse(id, name, path, repos, cachedRepo, result):
                state.newWorkspaceForm.isCreating = false
                switch result {
                case .success:
                    let workspace = WorkspaceState(
                        id: id,
                        name: name,
                        path: path,
                        repos: repos,
                        tabs: [.terminal(TerminalTabState(workingDirectory: path))]
                    )
                    state.workspaces.append(workspace)
                    state.activeWorkspaceID = id
                    if let cachedRepo, !state.cachedRepos.contains(where: { $0.remoteURL == cachedRepo.remoteURL }) {
                        state.cachedRepos.append(cachedRepo)
                    }
                    state.newWorkspaceForm = NewWorkspaceFeature.State()
                    state.lastErrorMessage = nil
                    return .send(.persistSession)
                case .failure(let message):
                    state.lastErrorMessage = message
                    return .none
                }

            case let .addRepositoryResponse(workspaceID, repo, cachedRepo, result):
                state.addRepositoryForm.isAdding = false
                switch result {
                case .success:
                    guard let workspaceIndex = state.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return .none }
                    state.workspaces[workspaceIndex].repos.append(repo)
                    if let cachedRepo, !state.cachedRepos.contains(where: { $0.remoteURL == cachedRepo.remoteURL }) {
                        state.cachedRepos.append(cachedRepo)
                    }
                    state.addRepositoryForm = AddRepositoryFeature.State()
                    state.lastErrorMessage = nil
                    return .send(.persistSession)
                case .failure(let message):
                    state.lastErrorMessage = message
                    return .none
                }

            case .deleteWorkspace(let id):
                guard let workspace = state.workspaces.first(where: { $0.id == id }) else { return .none }
                return .run { send in
                    do {
                        for repo in workspace.repos {
                            try await gitService.removeWorktree(bareRepo: repo.bareRepoPath, worktreePath: repo.worktreePath)
                        }
                        try? fileManager.removeItem(at: workspace.path)
                        await send(.deleteWorkspaceResponse(id, .success))
                    } catch {
                        await send(.deleteWorkspaceResponse(id, .failure(error.localizedDescription)))
                    }
                }

            case let .deleteWorkspaceResponse(id, result):
                switch result {
                case .success:
                    state.workspaces.removeAll { $0.id == id }
                    if state.activeWorkspaceID == id {
                        state.activeWorkspaceID = state.workspaces.first?.id
                    }
                    state.lastErrorMessage = nil
                    return .send(.persistSession)
                case .failure(let message):
                    state.lastErrorMessage = message
                    return .none
                }

            case .closeWorkspace(let id):
                state.workspaces.removeAll { $0.id == id }
                if state.activeWorkspaceID == id {
                    state.activeWorkspaceID = state.workspaces.first?.id
                }
                return .send(.persistSession)

            case .persistSession:
                let snapshot = state.sessionSnapshot()
                state.lastPersistenceSnapshot = snapshot
                return .run { send in
                    do {
                        try sessionStore.save(snapshot)
                        await send(.sessionPersisted(.success))
                    } catch {
                        await send(.sessionPersisted(.failure(error.localizedDescription)))
                    }
                }

            case .sessionPersisted(let result):
                switch result {
                case .success:
                    state.lastErrorMessage = nil
                case .failure(let message):
                    state.lastErrorMessage = message
                }
                return .none
            }
        }
    }

    private func closeTab(_ id: UUID, in workspace: inout WorkspaceState) {
        guard let index = workspace.tabs.firstIndex(where: { $0.id == id }) else { return }
        workspace.tabs.remove(at: index)
        if workspace.activeTabID == id {
            workspace.activeTabID = workspace.tabs.indices.contains(index) ? workspace.tabs[index].id : workspace.tabs.last?.id
        }
    }

    private func paste(_ content: String, intoActiveTerminalIn workspace: inout WorkspaceState) {
        guard let tabIndex = workspace.activeTabIndex,
              case .terminal(var terminal) = workspace.tabs[tabIndex]
        else { return }
        terminal.pendingPaste = content
        workspace.tabs[tabIndex] = .terminal(terminal)
    }

    private static func repositoryName(from remoteURL: String) -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = trimmed.split(separator: "/").last.map(String.init) ?? "repo"
        return last.replacingOccurrences(of: ".git", with: "")
    }

    private func availableWorktreePath(for repoName: String, in workspacePath: URL) -> URL {
        var candidate = workspacePath.appending(path: repoName, directoryHint: .isDirectory)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = workspacePath.appending(path: "\(repoName)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
    }
}

@Reducer
public struct WorkspaceFeature: Sendable {
    public typealias State = AppFeature.WorkspaceState
    public enum Action: Equatable, Sendable {
        case selectTab(index: Int)
        case closeTab(UUID)
        case addTerminalTab(UUID)
        case addCodeReviewTab(UUID)
        case tab(UUID, TabFeature.Action)
        case board(BoardFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selectTab(let index):
                guard state.tabs.indices.contains(index) else { return .none }
                state.activeTabID = state.tabs[index].id
                return .none
            case .closeTab(let id):
                guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return .none }
                state.tabs.remove(at: index)
                if state.activeTabID == id {
                    state.activeTabID = state.tabs.indices.contains(index) ? state.tabs[index].id : state.tabs.last?.id
                }
                return .none
            case .addTerminalTab(let id):
                state.tabs.append(.terminal(AppFeature.TerminalTabState(id: id, workingDirectory: state.path)))
                state.activeTabID = id
                return .none
            case .addCodeReviewTab(let id):
                state.tabs.append(.codeReview(AppFeature.CodeReviewTabState(id: id)))
                state.activeTabID = id
                return .none
            case .tab, .board:
                return .none
            }
        }
    }
}

@Reducer
public struct TabFeature: Sendable {
    public typealias State = AppFeature.TabState
    public enum Action: Equatable, Sendable {
        case terminal(TerminalTabFeature.Action)
        case codeReview(CodeReviewFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch (state, action) {
            case (.terminal(var terminal), .terminal(let action)):
                _ = TerminalTabFeature().reduce(into: &terminal, action: action)
                state = .terminal(terminal)
                return .none
            case (.codeReview(var review), .codeReview(let action)):
                _ = CodeReviewFeature().reduce(into: &review, action: action)
                state = .codeReview(review)
                return .none
            default:
                return .none
            }
        }
    }
}

@Reducer
public struct TerminalTabFeature: Sendable {
    public typealias State = AppFeature.TerminalTabState
    public enum Action: Equatable, Sendable {
        case output(String)
        case paste(String)
        case pasteConsumed
        case resumeMetadataChanged(TerminalResumeSnapshot?)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .output(let output):
                state.outputBuffer += output
                if state.outputBuffer.count > 50_000 {
                    state.outputBuffer.removeFirst(state.outputBuffer.count - 50_000)
                }
                return .none
            case .paste(let content):
                state.pendingPaste = content
                return .none
            case .pasteConsumed:
                state.pendingPaste = nil
                return .none
            case .resumeMetadataChanged(let resume):
                state.resume = resume
                return .none
            }
        }
    }
}

@Reducer
public struct CodeReviewFeature: Sendable {
    public typealias State = AppFeature.CodeReviewTabState
    public enum Action: Equatable, Sendable {
        case flow(CodeReviewFlowFeature.Action)
        case sessionLoaded(CodeReviewFlowFeature.State)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .flow(let action):
                guard var flow = state.flow else { return .none }
                _ = CodeReviewFlowFeature().reduce(into: &flow, action: action)
                state.flow = flow
                return .none
            case .sessionLoaded(let flow):
                state.flow = flow
                return .none
            }
        }
    }
}

@Reducer
public struct BoardFeature: Sendable {
    public struct State: Equatable, Sendable {
        public var items: [BoardItem]
        public init(items: [BoardItem] = []) {
            self.items = items
        }
    }

    public enum Action: Equatable, Sendable {
        case send(content: String, source: String, id: UUID, createdAt: Date)
        case remove(UUID)
        case paste(UUID)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .send(content, source, id, createdAt):
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return .none }
                state.items.insert(BoardItem(id: id, content: trimmed, source: source, createdAt: createdAt), at: 0)
                return .none
            case .remove(let id):
                state.items.removeAll { $0.id == id }
                return .none
            case .paste:
                return .none
            }
        }
    }
}

@Reducer
public struct NewWorkspaceFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var name: String
        public var selectedCachedRepoID: UUID?
        public var remoteURL: String
        public var branch: String
        public var isCreating: Bool

        public init(
            name: String = "",
            selectedCachedRepoID: UUID? = nil,
            remoteURL: String = "",
            branch: String = "main",
            isCreating: Bool = false
        ) {
            self.name = name
            self.selectedCachedRepoID = selectedCachedRepoID
            self.remoteURL = remoteURL
            self.branch = branch
            self.isCreating = isCreating
        }

        public var sanitizedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var sanitizedRemoteURL: String {
            remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var sanitizedBranch: String {
            let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "main" : value
        }

        public var isValid: Bool {
            !sanitizedName.isEmpty
        }
    }

    public enum Action: Equatable, Sendable {
        case nameChanged(String)
        case selectedCachedRepoChanged(UUID?)
        case remoteURLChanged(String)
        case branchChanged(String)
        case createButtonTapped(id: UUID)
        case cancelButtonTapped
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .nameChanged(let value):
                state.name = value
            case .selectedCachedRepoChanged(let value):
                state.selectedCachedRepoID = value
            case .remoteURLChanged(let value):
                state.remoteURL = value
            case .branchChanged(let value):
                state.branch = value
            case .createButtonTapped:
                state.isCreating = state.isValid
            case .cancelButtonTapped:
                state = State()
            }
            return .none
        }
    }
}

@Reducer
public struct AddRepositoryFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var selectedCachedRepoID: UUID?
        public var remoteURL: String
        public var branch: String
        public var isAdding: Bool

        public init(
            selectedCachedRepoID: UUID? = nil,
            remoteURL: String = "",
            branch: String = "main",
            isAdding: Bool = false
        ) {
            self.selectedCachedRepoID = selectedCachedRepoID
            self.remoteURL = remoteURL
            self.branch = branch
            self.isAdding = isAdding
        }

        public var sanitizedRemoteURL: String {
            remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var sanitizedBranch: String {
            let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "main" : value
        }

        public var isValid: Bool {
            selectedCachedRepoID != nil || !sanitizedRemoteURL.isEmpty
        }
    }

    public enum Action: Equatable, Sendable {
        case selectedCachedRepoChanged(UUID?)
        case remoteURLChanged(String)
        case branchChanged(String)
        case addButtonTapped
        case cancelButtonTapped
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selectedCachedRepoChanged(let value):
                state.selectedCachedRepoID = value
            case .remoteURLChanged(let value):
                state.remoteURL = value
            case .branchChanged(let value):
                state.branch = value
            case .addButtonTapped:
                state.isAdding = state.isValid
            case .cancelButtonTapped:
                state = State()
            }
            return .none
        }
    }
}

@Reducer
public struct SettingsFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var config: AppConfig

        public init(config: AppConfig) {
            self.config = config
        }
    }

    public enum Action: Equatable, Sendable {
        case workspacesRootChanged(String)
        case cacheRootChanged(String)
        case notificationPatternChanged(index: Int, value: String)
        case addNotificationPatternButtonTapped
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .workspacesRootChanged(let value):
                state.config.workspacesRoot = URL(fileURLWithPath: value, isDirectory: true)
            case .cacheRootChanged(let value):
                state.config.cacheRoot = URL(fileURLWithPath: value, isDirectory: true)
            case let .notificationPatternChanged(index, value):
                guard state.config.notificationPatterns.indices.contains(index) else { return .none }
                state.config.notificationPatterns[index] = value
            case .addNotificationPatternButtonTapped:
                state.config.notificationPatterns.append("")
            }
            return .none
        }
    }
}
