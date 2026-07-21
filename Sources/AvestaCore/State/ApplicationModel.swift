import Foundation
import Observation

public struct TerminalInputRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public init(id: UUID = UUID(), text: String) { self.id = id; self.text = text }
}

@Observable
@MainActor
public final class ApplicationModel {
    public private(set) var workspaces: [WorkspaceRecord] = []
    public private(set) var repositorySources: [RepositorySourceRecord] = []
    public var activeWorkspaceID: UUID?
    public private(set) var reviewStates: [UUID: WorkspaceReviewState] = [:]
    public private(set) var repositoryOperations: [UUID: RepositoryOperationState] = [:]
    public private(set) var dirtyCounts: [UUID: Int] = [:]
    public private(set) var attentionWorkspaceIDs: Set<UUID> = []
    public private(set) var pendingTerminalInput: [UUID: TerminalInputRequest] = [:]
    public private(set) var terminalScrollback: [UUID: ScrollbackPolicy] = [:]
    public private(set) var lastFocusedTerminalID: [UUID: UUID] = [:]
    public var globalScrollback: ScrollbackPolicy = .limited(lines: 10_000)
    public private(set) var defaultBaseBranch = "origin/main"
    public var errorMessage: String?
    public var isLoaded = false

    public let config: AppConfig
    private let repository: any StateRepository
    private let git: GitService

    public init(config: AppConfig = .default, repository: (any StateRepository)? = nil, git: GitService? = nil) throws {
        self.config = config
        self.repository = try repository ?? SQLiteStateRepository(databaseURL: config.databaseURL)
        self.git = git ?? GitService(cacheRoot: config.cacheRoot)
    }

    public func workspacePath(forName name: String) -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let component = (trimmed.isEmpty ? "workspace" : trimmed)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return config.workspacesRoot.appending(path: component, directoryHint: .isDirectory)
    }

    public var activeWorkspace: WorkspaceRecord? {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces.first
    }

    public func load() async {
        do {
            try await repository.initialize()
            workspaces = try await repository.loadWorkspaces()
            repositorySources = try await repository.loadRepositorySources()
            globalScrollback = try await repository.setting(ScrollbackPolicy.self, forKey: "terminal.globalScrollback") ?? .limited(lines: 10_000)
            defaultBaseBranch = try await repository.setting(String.self, forKey: "git.defaultBaseBranch") ?? "origin/main"
            try await loadTerminalPolicies()
            activeWorkspaceID = activeWorkspaceID.flatMap { id in workspaces.contains { $0.id == id } ? id : nil } ?? workspaces.first?.id
            for workspace in workspaces {
                let baselineValue = try await repository.setting(
                    String.self,
                    forKey: Self.reviewBaselineSettingKey(workspaceID: workspace.id)
                ) ?? ReviewBaseline.head.storageValue
                let mode = try await repository.setting(
                    ReviewDisplayMode.self,
                    forKey: Self.reviewModeSettingKey(workspaceID: workspace.id)
                ) ?? .unified
                let repositoryFilter = try await repository.setting(
                    UUID.self,
                    forKey: Self.reviewRepositoryFilterSettingKey(workspaceID: workspace.id)
                )
                reviewStates[workspace.id] = WorkspaceReviewState(
                    workspaceID: workspace.id,
                    baseline: ReviewBaseline(storageValue: baselineValue),
                    mode: mode,
                    repositoryFilter: repositoryFilter,
                    historicalSnapshots: try await repository.snapshots(workspaceID: workspace.id)
                )
            }
            isLoaded = true
            await refreshSidebarMetadata()
        } catch { report(error) }
    }

    public func createWorkspace(name: String, path: URL, repositories drafts: [RepositoryDraft] = []) async {
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let workspace = try await repository.createWorkspace(name: name, path: path)
            workspaces.append(workspace)
            activeWorkspaceID = workspace.id
            reviewStates[workspace.id] = WorkspaceReviewState(workspaceID: workspace.id)
            for draft in drafts { await addRepository(draft, to: workspace.id) }
            await reload()
        } catch { report(error) }
    }

    public func createWorkspace(name: String, repositories drafts: [RepositoryDraft] = []) async {
        await createWorkspace(name: name, path: workspacePath(forName: name), repositories: drafts)
    }

    /// Add or fetch a repository in the global shared-clone bank. This does not
    /// create a workspace worktree; worktrees are created when a bank entry is
    /// selected for a workspace.
    public func addRepositoryToBank(remoteURL: String, defaultBaseBranch: String? = nil) async {
        let value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            let cachePath = await git.sharedClonePath(remoteURL: value)
            let baseBranch = defaultBaseBranch?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? defaultBaseBranch! : self.defaultBaseBranch
            let source = try await repository.upsertRepositorySource(remoteURL: value, cachePath: cachePath, defaultBaseBranch: baseBranch)
            try await git.ensureSharedClone(remoteURL: value, at: source.cachePath)
            try await repository.updateSourceFetchDate(id: source.id, date: Date())
            await reload()
        } catch { report(error) }
    }

    public func setDefaultBaseBranch(_ branch: String) async {
        let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try await repository.setSetting(value, forKey: "git.defaultBaseBranch")
            defaultBaseBranch = value
        } catch { report(error) }
    }

    public func setRepositoryBaseBranch(sourceID: UUID, branch: String) async {
        let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try await repository.updateSourceDefaultBaseBranch(id: sourceID, branch: value)
            repositorySources = try await repository.loadRepositorySources()
        } catch { report(error) }
    }

    public func reorderRepositorySources(fromOffsets: IndexSet, toOffset: Int) async {
        var reordered = repositorySources
        let moving = fromOffsets.sorted().map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) { reordered.remove(at: index) }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        reordered.insert(contentsOf: moving, at: max(0, min(reordered.count, toOffset - removedBeforeDestination)))
        do {
            try await repository.reorderRepositorySources(reordered.map(\.id))
            repositorySources = reordered.enumerated().map { index, source in
                var source = source
                source.sortIndex = index
                return source
            }
        } catch { report(error) }
    }

    public func deleteRepositorySource(id: UUID) async {
        guard let source = repositorySources.first(where: { $0.id == id }) else { return }
        let consumers = workspaces.filter { $0.repositories.contains { $0.sourceID == id } }
        guard consumers.isEmpty else {
            errorMessage = "Cannot delete \(source.repositoryIdentity) because it is used by: \(consumers.map(\.name).joined(separator: ", "))"
            return
        }
        do {
            try await repository.deleteRepositorySource(id: id)
            try await git.removeSharedClone(at: source.cachePath)
            await reload()
        } catch { report(error) }
    }

    public func fetchRepositorySource(id: UUID) async {
        guard let source = repositorySources.first(where: { $0.id == id }) else { return }
        do {
            try await git.fetch(sharedClone: source.cachePath)
            try await repository.updateSourceFetchDate(id: source.id, date: Date())
            await reload()
        } catch { report(error) }
    }

    public func renameWorkspace(id: UUID, name: String) async {
        do { try await repository.renameWorkspace(id: id, name: name); await reload() } catch { report(error) }
    }

    public func reorderWorkspaces(fromOffsets: IndexSet, toOffset: Int) async {
        var reordered = workspaces
        let moving = fromOffsets.sorted().map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) { reordered.remove(at: index) }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        reordered.insert(contentsOf: moving, at: max(0, min(reordered.count, toOffset - removedBeforeDestination)))
        do { try await repository.reorderWorkspaces(reordered.map(\.id)); workspaces = reordered } catch { report(error) }
    }

    public func deleteWorkspace(id: UUID) async {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        do {
            for item in workspace.repositories {
                if let source = repositorySources.first(where: { $0.id == item.sourceID }) {
                    try await git.removeWorktree(sharedClone: source.cachePath, path: item.worktreePath)
                }
            }
            if FileManager.default.fileExists(atPath: workspace.path.path) { try FileManager.default.removeItem(at: workspace.path) }
            try await repository.deleteWorkspace(id: id)
            await reload()
        } catch { report(error) }
    }

    public func addRepository(_ draft: RepositoryDraft, to workspaceID: UUID) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        repositoryOperations[draft.id] = RepositoryOperationState(id: draft.id, phase: .cloning, progress: 0.1)
        do {
            let source: RepositorySourceRecord
            if let id = draft.cachedSourceID, let cached = repositorySources.first(where: { $0.id == id }) {
                source = cached
                repositoryOperations[draft.id] = RepositoryOperationState(id: draft.id, phase: .fetching, progress: 0.4)
                try await git.fetch(sharedClone: source.cachePath)
            } else {
                let cachePath = await git.sharedClonePath(remoteURL: draft.remoteURL)
                source = try await repository.upsertRepositorySource(remoteURL: draft.remoteURL, cachePath: cachePath, defaultBaseBranch: defaultBaseBranch)
                try await git.ensureSharedClone(remoteURL: draft.remoteURL, at: cachePath)
            }
            try await repository.updateSourceFetchDate(id: source.id, date: Date())
            repositoryOperations[draft.id] = RepositoryOperationState(id: draft.id, phase: .creatingWorktree, progress: 0.75)
            let name = source.cachePath.deletingPathExtension().lastPathComponent.replacingOccurrences(of: #"-[0-9a-f]{24}$"#, with: "", options: .regularExpression)
            let destination = availablePath(named: name, in: workspace.path)
            let branch = draft.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? workspaceBranchName(workspace.name) : draft.branch
            let baseBranch = draft.baseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? source.defaultBaseBranch : draft.baseBranch
            try await git.createWorktree(sharedClone: source.cachePath, branch: branch, destination: destination, baseBranch: baseBranch)
            let item = WorkspaceRepositoryRecord(workspaceID: workspace.id, sourceID: source.id, name: name, worktreePath: destination, branch: branch, baseBranch: baseBranch, sortIndex: workspace.repositories.count)
            try await repository.addWorkspaceRepository(item)
            repositoryOperations[draft.id] = RepositoryOperationState(id: draft.id, phase: .complete, progress: 1)
            await reload()
        } catch {
            repositoryOperations[draft.id] = RepositoryOperationState(id: draft.id, phase: .failed, progress: 0, message: error.localizedDescription)
            report(error)
        }
    }

    public func removeRepository(_ id: UUID, from workspaceID: UUID) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }), let item = workspace.repositories.first(where: { $0.id == id }), let source = repositorySources.first(where: { $0.id == item.sourceID }) else { return }
        do { try await git.removeWorktree(sharedClone: source.cachePath, path: item.worktreePath); try await repository.removeWorkspaceRepository(id: id); await reload() } catch { report(error) }
    }

    public func createTab(kind: TabKind, workspaceID: UUID, workingDirectory: URL? = nil, beside: Bool = false) async -> UUID? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }
        let directory = workingDirectory ?? workspace.path
        let tab = TabRecord(workspaceID: workspaceID, kind: kind, title: kind == .terminal ? "Terminal" : "Review", sortIndex: workspace.tabs.count, workingDirectory: kind == .terminal ? directory : nil, repositoryID: workspace.repositories.first { $0.worktreePath == directory }?.id)
        do {
            let terminal = kind == .terminal ? TerminalSessionRecord(tabID: tab.id, workingDirectory: directory, scrollback: globalScrollback) : nil
            try await repository.createTab(tab, terminal: terminal)
            if beside { try await repository.dockCompanion(workspaceID: workspaceID, tabID: tab.id, ratio: workspace.layout.splitRatio) }
            else { try await repository.selectTab(workspaceID: workspaceID, tabID: tab.id) }
            await reload()
            if kind == .review { await refreshReview(workspaceID: workspaceID, reason: "open") }
            return tab.id
        } catch { report(error); return nil }
    }

    public func selectTab(workspaceID: UUID, tabID: UUID) async {
        do { try await repository.selectTab(workspaceID: workspaceID, tabID: tabID); await reload() } catch { report(error) }
    }

    public func renameTab(id: UUID, title: String) async {
        do { try await repository.renameTab(id: id, title: title); await reload() } catch { report(error) }
    }

    public func moveTab(workspaceID: UUID, tabID: UUID, before targetID: UUID) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }), let source = workspace.tabs.firstIndex(where: { $0.id == tabID }), let target = workspace.tabs.firstIndex(where: { $0.id == targetID }), source != target else { return }
        var tabs = workspace.tabs
        let item = tabs.remove(at: source)
        tabs.insert(item, at: target > source ? target - 1 : target)
        do { try await repository.reorderTabs(workspaceID: workspaceID, ids: tabs.map(\.id)); await reload() } catch { report(error) }
    }

    public func closeTab(_ id: UUID, workspaceID: UUID) async {
        do { try await repository.deleteTab(id: id); await reload() } catch { report(error) }
    }

    public func closeOtherTabs(keeping id: UUID, workspaceID: UUID) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        for tab in workspace.tabs where tab.id != id { try? await repository.deleteTab(id: tab.id) }
        await reload()
    }

    public func openBeside(tabID: UUID, workspaceID: UUID) async {
        do { try await repository.dockCompanion(workspaceID: workspaceID, tabID: tabID, ratio: activeWorkspace?.layout.splitRatio ?? 0.5); await reload() } catch { report(error) }
    }

    public func closeCompanion(workspaceID: UUID) async {
        do { try await repository.undockCompanion(workspaceID: workspaceID); await reload() } catch { report(error) }
    }

    public func updateSplit(workspaceID: UUID, ratio: Double, focusedTabID: UUID?) async {
        do { try await repository.updateSplit(workspaceID: workspaceID, ratio: ratio, focusedTabID: focusedTabID); await reload() } catch { report(error) }
    }

    public func terminalFocused(workspaceID: UUID, tabID: UUID) {
        lastFocusedTerminalID[workspaceID] = tabID
        attentionWorkspaceIDs.remove(workspaceID)
    }

    public func setGlobalScrollback(_ policy: ScrollbackPolicy) async {
        do { try await repository.setSetting(policy, forKey: "terminal.globalScrollback"); globalScrollback = policy } catch { report(error) }
    }

    public func setTerminalScrollback(tabID: UUID, policy: ScrollbackPolicy) async {
        do { try await repository.updateTerminalScrollback(tabID: tabID, policy: policy); terminalScrollback[tabID] = policy } catch { report(error) }
    }

    public func queueTerminalInput(tabID: UUID, text: String) {
        pendingTerminalInput[tabID] = TerminalInputRequest(text: text)
    }

    public func consumeTerminalInput(tabID: UUID, requestID: UUID) {
        if pendingTerminalInput[tabID]?.id == requestID { pendingTerminalInput[tabID] = nil }
    }

    public func sendAnnotationToTerminal(_ annotation: ReviewAnnotation, targetTabID: UUID? = nil) async {
        guard let workspace = workspaces.first(where: { $0.id == annotation.workspaceID }), let repositoryItem = workspace.repositories.first(where: { $0.id == annotation.repositoryID }) else { return }
        var tabID = targetTabID ?? lastFocusedTerminalID[workspace.id]
        if tabID == nil { tabID = await createTab(kind: .terminal, workspaceID: workspace.id, workingDirectory: repositoryItem.worktreePath, beside: true) }
        guard let tabID else { return }
        queueTerminalInput(tabID: tabID, text: TerminalReviewHandoff.format(repository: repositoryItem, filePath: annotation.filePath, side: annotation.side, startLine: annotation.startLine, endLine: annotation.endLine, excerpt: annotation.selectedCode, userText: annotation.userText))
    }

    @discardableResult
    public func sendReviewBundleToTerminal(workspaceID: UUID, annotations: [ReviewAnnotation], targetTabID: UUID) -> Bool {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }),
              workspace.tabs.contains(where: { $0.id == targetTabID && $0.kind == .terminal }),
              !annotations.isEmpty else { return false }
        queueTerminalInput(
            tabID: targetTabID,
            text: WorkspaceReviewBundleFormatter.format(workspace: workspace, annotations: annotations)
        )
        return true
    }

    public func refreshReview(workspaceID: UUID, reason: String = "refresh") async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        var state = reviewStates[workspaceID] ?? WorkspaceReviewState(workspaceID: workspaceID)
        state.isRefreshing = true
        state.errorMessage = nil
        reviewStates[workspaceID] = state
        do {
            let relativeReference: String?
            if case .branch(let reference) = state.baseline { relativeReference = reference } else { relativeReference = nil }
            let captureResult = await capture(workspace, relativeTo: relativeReference)
            let captured = captureResult.repositories
            let activeSession = try await repository.activeReviewSession(workspaceID: workspaceID)
            var snapshot = ReviewSnapshotRecord(workspaceID: workspaceID, activitySessionID: workspace.activitySessionID, reviewSessionID: activeSession?.id, fingerprint: GitService.workspaceFingerprint(captured), reason: relativeReference.map { "branch:\($0)" } ?? reason, repositories: captured)
            snapshot = try await repository.saveSnapshot(snapshot)
            // saveSnapshot returns a hydrated existing snapshot when the
            // fingerprint is unchanged and the original in-memory snapshot
            // when newly inserted. Loading it again would decompress every
            // file blob a second time during each refresh.
            let hydrated = snapshot
            let baseline = state.baseline
            let files = try await comparisonFiles(workspace: workspace, current: hydrated, baseline: baseline)
            let annotations = try await repository.annotations(workspaceID: workspaceID)
            let fingerprints = Set(captured.flatMap(\.files).map(\.fingerprint))
            for annotation in annotations {
                let outdated = !fingerprints.contains(annotation.anchorFingerprint)
                if outdated != annotation.isOutdated { try await repository.markAnnotationOutdated(id: annotation.id, isOutdated: outdated) }
            }
            state.files = files
            state.snapshot = hydrated
            state.annotations = try await repository.annotations(workspaceID: workspaceID)
            state.historicalSnapshots = try await repository.snapshots(workspaceID: workspaceID)
            state.repositoryErrors = captureResult.errors
            state.isRefreshing = false
            reviewStates[workspaceID] = state
            await refreshSidebarMetadata()
        } catch {
            state.isRefreshing = false
            state.errorMessage = error.localizedDescription
            reviewStates[workspaceID] = state
            report(error)
        }
    }

    public func setReviewBaseline(workspaceID: UUID, baseline: ReviewBaseline) async {
        var state = reviewStates[workspaceID] ?? WorkspaceReviewState(workspaceID: workspaceID)
        state.baseline = baseline
        reviewStates[workspaceID] = state
        do {
            try await repository.setSetting(
                baseline.storageValue,
                forKey: Self.reviewBaselineSettingKey(workspaceID: workspaceID)
            )
        } catch { report(error) }
        await refreshReview(workspaceID: workspaceID)
    }

    public func setReviewMode(workspaceID: UUID, mode: ReviewDisplayMode) async {
        var state = reviewStates[workspaceID] ?? WorkspaceReviewState(workspaceID: workspaceID)
        state.mode = mode
        reviewStates[workspaceID] = state
        do {
            try await repository.setSetting(
                mode,
                forKey: Self.reviewModeSettingKey(workspaceID: workspaceID)
            )
        } catch { report(error) }
    }

    public func setReviewRepositoryFilter(workspaceID: UUID, repositoryID: UUID?) async {
        var state = reviewStates[workspaceID] ?? WorkspaceReviewState(workspaceID: workspaceID)
        state.repositoryFilter = repositoryID
        reviewStates[workspaceID] = state
        do {
            if let repositoryID {
                try await repository.setSetting(
                    repositoryID,
                    forKey: Self.reviewRepositoryFilterSettingKey(workspaceID: workspaceID)
                )
            } else {
                try await repository.removeSetting(
                    forKey: Self.reviewRepositoryFilterSettingKey(workspaceID: workspaceID)
                )
            }
        } catch { report(error) }
    }

    public func saveAnnotation(workspaceID: UUID, repositoryID: UUID, file: WorkspaceFileDiff, kind: AnnotationKind, side: DiffSide, startLine: Int, endLine: Int, selectedCode: String, context: String, text: String) async -> ReviewAnnotation? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }
        do {
            let session = try await repository.ensureReviewSession(workspaceID: workspaceID, activitySessionID: workspace.activitySessionID)
            await refreshReview(workspaceID: workspaceID, reason: kind == .comment ? "comment" : "question")
            guard let snapshot = reviewStates[workspaceID]?.snapshot else { return nil }
            let fingerprint = snapshot.repositories.first { $0.repositoryID == repositoryID }?.files.first { $0.path == file.diff.path }?.fingerprint ?? ""
            let annotation = ReviewAnnotation(workspaceID: workspaceID, activitySessionID: workspace.activitySessionID, reviewSessionID: session.id, repositoryID: repositoryID, snapshotID: snapshot.id, kind: kind, filePath: file.diff.path, side: side, startLine: startLine, endLine: endLine, anchorFingerprint: fingerprint, selectedCode: selectedCode, context: context, userText: text)
            try await repository.saveAnnotation(annotation)
            await refreshReview(workspaceID: workspaceID, reason: kind == .comment ? "comment" : "question")
            return annotation
        } catch { report(error); return nil }
    }

    @discardableResult
    public func updateAnnotationText(_ annotation: ReviewAnnotation, text: String) async -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        do {
            try await repository.updateAnnotationText(id: annotation.id, text: value)
            await reloadAnnotations(workspaceID: annotation.workspaceID)
            return true
        } catch { report(error); return false }
    }

    @discardableResult
    public func deleteAnnotation(_ annotation: ReviewAnnotation) async -> Bool {
        do {
            try await repository.deleteAnnotation(id: annotation.id)
            await reloadAnnotations(workspaceID: annotation.workspaceID)
            return true
        } catch { report(error); return false }
    }

    public func askAssistant(annotation: ReviewAnnotation, provider: AssistantProvider) async {
        guard let workspace = workspaces.first(where: { $0.id == annotation.workspaceID }), let repositoryItem = workspace.repositories.first(where: { $0.id == annotation.repositoryID }) else { return }
        let thread = AssistantThreadRecord(id: UUID(), annotationID: annotation.id, provider: provider, providerSessionID: nil, model: nil, createdAt: Date())
        do {
            try await repository.saveAssistantThread(thread)
            guard let client = await AssistantClientRegistry.shared.client(for: provider) else { throw AssistantClientError.unavailable("\(provider.rawValue.capitalized) SDK is not configured") }
            let question = AssistantQuestion(repositoryName: repositoryItem.name, repositoryPath: repositoryItem.worktreePath, filePath: annotation.filePath, side: annotation.side, startLine: annotation.startLine, endLine: annotation.endLine, selectedCode: annotation.selectedCode, surroundingContext: annotation.context, question: annotation.userText)
            let stream = try await client.ask(question, policy: .reviewReadOnly)
            var message = AssistantMessageRecord(id: UUID(), threadID: thread.id, role: .assistant, content: "", isStreaming: true, errorCode: nil, createdAt: Date())
            try await repository.saveAssistantMessage(message)
            for try await chunk in stream.chunks { message.content += chunk; try await repository.saveAssistantMessage(message) }
            message.isStreaming = false
            try await repository.saveAssistantMessage(message)
        } catch {
            let normalized = error as? AssistantClientError ?? .provider(error.localizedDescription)
            try? await repository.saveAssistantMessage(AssistantMessageRecord(id: UUID(), threadID: thread.id, role: .error, content: normalized.localizedDescription, isStreaming: false, errorCode: normalized.code, createdAt: Date()))
            report(normalized)
        }
    }

    public func finishReview(workspaceID: UUID) async {
        guard let snapshot = reviewStates[workspaceID]?.snapshot else { return }
        do { try await repository.finishReview(workspaceID: workspaceID, snapshot: snapshot); await refreshReview(workspaceID: workspaceID, reason: "finish") } catch { report(error) }
    }

    public func startNewActivitySession(workspaceID: UUID) async {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        do {
            let captured = await capture(workspace).repositories
            let snapshot = ReviewSnapshotRecord(workspaceID: workspaceID, activitySessionID: workspace.activitySessionID, fingerprint: GitService.workspaceFingerprint(captured), reason: "activity-session", repositories: captured)
            _ = try await repository.startActivitySession(workspaceID: workspaceID, snapshot: snapshot)
            await reload()
        } catch { report(error) }
    }

    public func terminalOutputObserved(workspaceID: UUID, tabID: UUID, kind: String, summary: String) async {
        attentionWorkspaceIDs.insert(workspaceID)
        try? await repository.saveTerminalEvent(tabID: tabID, kind: kind, summary: summary, metadata: nil)
        try? await repository.saveNotification(NotificationRecord(id: UUID(), workspaceID: workspaceID, tabID: tabID, title: "Terminal Needs Attention", body: summary, createdAt: Date(), readAt: nil))
    }

    private func comparisonFiles(workspace: WorkspaceRecord, current: ReviewSnapshotRecord, baseline: ReviewBaseline) async throws -> [WorkspaceFileDiff] {
        let names = Dictionary(uniqueKeysWithValues: workspace.repositories.map { ($0.id, $0.name) })
        switch baseline {
        case .head:
            return current.repositories.flatMap { repositorySnapshot in
                repositorySnapshot.files.map { WorkspaceFileDiff(repositoryID: repositorySnapshot.repositoryID, repositoryName: names[repositorySnapshot.repositoryID] ?? "Repository", diff: GitService.fileDiff(from: $0), oldContent: $0.oldContent, newContent: $0.newContent) }
            }
        case .branch:
            return current.repositories.flatMap { repositorySnapshot in
                repositorySnapshot.files.map { WorkspaceFileDiff(repositoryID: repositorySnapshot.repositoryID, repositoryName: names[repositorySnapshot.repositoryID] ?? "Repository", diff: GitService.fileDiff(from: $0), oldContent: $0.oldContent, newContent: $0.newContent) }
            }
        case .snapshot(let id):
            guard let old = try await repository.loadSnapshot(id: id) else { return [] }
            return GitService.compare(old: old, new: current, repositoryNames: names)
        case .activitySessionStart:
            guard let old = try await repository.activityBaselineSnapshot(workspaceID: workspace.id) else { return [] }
            return GitService.compare(old: old, new: current, repositoryNames: names)
        case .lastCompletedReview:
            guard let old = try await repository.lastCompletedReviewSnapshot(workspaceID: workspace.id) else { return current.repositories.flatMap { repositorySnapshot in repositorySnapshot.files.map { WorkspaceFileDiff(repositoryID: repositorySnapshot.repositoryID, repositoryName: names[repositorySnapshot.repositoryID] ?? "Repository", diff: GitService.fileDiff(from: $0), oldContent: $0.oldContent, newContent: $0.newContent) } } }
            return GitService.compare(old: old, new: current, repositoryNames: names)
        }
    }

    private func capture(_ workspace: WorkspaceRecord, relativeTo reference: String? = nil) async -> (repositories: [ReviewSnapshotRepository], errors: [UUID: String]) {
        var result: [ReviewSnapshotRepository] = []
        var errors: [UUID: String] = [:]
        for repositoryItem in workspace.repositories {
            do { result.append(try await git.capture(repository: repositoryItem, relativeTo: reference)) }
            catch { errors[repositoryItem.id] = error.localizedDescription }
        }
        return (result, errors)
    }

    private func reload() async {
        do {
            workspaces = try await repository.loadWorkspaces()
            repositorySources = try await repository.loadRepositorySources()
            try await loadTerminalPolicies()
            if !workspaces.contains(where: { $0.id == activeWorkspaceID }) { activeWorkspaceID = workspaces.first?.id }
        } catch { report(error) }
    }

    private func reloadAnnotations(workspaceID: UUID) async {
        do {
            var state = reviewStates[workspaceID] ?? WorkspaceReviewState(workspaceID: workspaceID)
            state.annotations = try await repository.annotations(workspaceID: workspaceID)
            reviewStates[workspaceID] = state
        } catch { report(error) }
    }

    private func refreshSidebarMetadata() async {
        var counts: [UUID: Int] = [:]
        for workspace in workspaces {
            var count = 0
            for repositoryItem in workspace.repositories { count += (try? await git.dirtyChangeCount(repository: repositoryItem.worktreePath)) ?? 0 }
            counts[workspace.id] = count
        }
        dirtyCounts = counts
    }

    private func loadTerminalPolicies() async throws {
        var policies: [UUID: ScrollbackPolicy] = [:]
        for tab in workspaces.flatMap(\.tabs) where tab.kind == .terminal {
            if let terminal = try await repository.terminalSession(tabID: tab.id) { policies[tab.id] = terminal.scrollback }
        }
        terminalScrollback = policies
    }

    static func reviewBaselineSettingKey(workspaceID: UUID) -> String {
        "review.\(workspaceID.uuidString).baseline"
    }

    static func reviewModeSettingKey(workspaceID: UUID) -> String {
        "review.\(workspaceID.uuidString).mode"
    }

    static func reviewRepositoryFilterSettingKey(workspaceID: UUID) -> String {
        "review.\(workspaceID.uuidString).repositoryFilter"
    }

    private func availablePath(named name: String, in root: URL) -> URL {
        var candidate = root.appending(path: name, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) { candidate = root.appending(path: "\(name)-\(suffix)", directoryHint: .isDirectory); suffix += 1 }
        return candidate
    }

    private func workspaceBranchName(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "[^a-z0-9._/-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-/."))
        return value.isEmpty ? "workspace" : value
    }

    private func report(_ error: Error) { errorMessage = error.localizedDescription }
}
