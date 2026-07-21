import Foundation

public struct WorkspaceRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: URL
    public var sortIndex: Int
    public var createdAt: Date
    public var repositories: [WorkspaceRepositoryRecord]
    public var tabs: [TabRecord]
    public var layout: WorkspaceLayoutRecord
    public var activitySessionID: UUID

    public init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        repositories: [WorkspaceRepositoryRecord] = [],
        tabs: [TabRecord] = [],
        layout: WorkspaceLayoutRecord? = nil,
        activitySessionID: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.repositories = repositories
        self.tabs = tabs
        self.layout = layout ?? WorkspaceLayoutRecord(workspaceID: id)
        self.activitySessionID = activitySessionID
    }

    public var activeTab: TabRecord? {
        tabs.first { $0.id == layout.primaryTabID } ?? tabs.first
    }

    public var companionTab: TabRecord? {
        guard let id = layout.companionTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    public func adjacentTabID(offset: Int) -> UUID? {
        guard !tabs.isEmpty else { return nil }
        let activeIndex = activeTab.flatMap { active in tabs.firstIndex { $0.id == active.id } } ?? 0
        let wrappedIndex = (activeIndex + offset % tabs.count + tabs.count) % tabs.count
        return tabs[wrappedIndex].id
    }

    /// Matches common macOS/browser tab behavior: Command-1 through Command-8
    /// select that position, while Command-9 selects the final tab.
    public func tabID(shortcutNumber: Int) -> UUID? {
        guard (1...9).contains(shortcutNumber), !tabs.isEmpty else { return nil }
        if shortcutNumber == 9 { return tabs.last?.id }
        let index = shortcutNumber - 1
        return tabs.indices.contains(index) ? tabs[index].id : nil
    }

    public var branchSummary: String {
        let branches = Array(Set(repositories.map(\.branch))).sorted()
        if branches.isEmpty { return "Empty" }
        if branches.count == 1 { return branches[0] }
        return "\(branches.count) branches"
    }
}

public struct RepositorySourceRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var canonicalRemoteURL: String
    public var displayRemoteURL: String
    public var cachePath: URL
    public var sortIndex: Int
    public var createdAt: Date
    public var lastFetchedAt: Date?
    public var defaultBaseBranch: String

    /// A compact, host-independent identity for display and workspace pickers.
    /// The full remote URL remains authoritative for cloning and deduplication.
    public var repositoryIdentity: String { Self.identity(from: displayRemoteURL) }

    public init(
        id: UUID = UUID(),
        canonicalRemoteURL: String,
        displayRemoteURL: String,
        cachePath: URL,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        lastFetchedAt: Date? = nil,
        defaultBaseBranch: String = "origin/main"
    ) {
        self.id = id
        self.canonicalRemoteURL = canonicalRemoteURL
        self.displayRemoteURL = displayRemoteURL
        self.cachePath = cachePath
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.lastFetchedAt = lastFetchedAt
        self.defaultBaseBranch = defaultBaseBranch
    }

    public static func identity(from remoteURL: String) -> String {
        var value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git@"), let separator = value.firstIndex(of: ":") {
            value = String(value[value.index(after: separator)...])
        } else if let components = URLComponents(string: value), !components.path.isEmpty {
            value = components.path
        } else if let separator = value.firstIndex(of: ":"), !value.contains("//") {
            value = String(value[value.index(after: separator)...])
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value.isEmpty ? remoteURL : value
    }
}

public struct WorkspaceRepositoryRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var sourceID: UUID
    public var name: String
    public var worktreePath: URL
    public var branch: String
    public var baseBranch: String?
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        workspaceID: UUID,
        sourceID: UUID,
        name: String,
        worktreePath: URL,
        branch: String,
        baseBranch: String? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.sourceID = sourceID
        self.name = name
        self.worktreePath = worktreePath
        self.branch = branch
        self.baseBranch = baseBranch
        self.sortIndex = sortIndex
    }
}

public enum TabKind: String, Codable, CaseIterable, Sendable {
    case terminal
    case review
}

public struct TabRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var kind: TabKind
    public var title: String
    public var sortIndex: Int
    public var workingDirectory: URL?
    public var repositoryID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        workspaceID: UUID,
        kind: TabKind,
        title: String,
        sortIndex: Int = 0,
        workingDirectory: URL? = nil,
        repositoryID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.kind = kind
        self.title = title
        self.sortIndex = sortIndex
        self.workingDirectory = workingDirectory
        self.repositoryID = repositoryID
        self.createdAt = createdAt
    }
}

public struct WorkspaceLayoutRecord: Codable, Hashable, Sendable {
    public var workspaceID: UUID
    public var primaryTabID: UUID?
    public var companionTabID: UUID?
    public var focusedTabID: UUID?
    public var splitRatio: Double

    public init(
        workspaceID: UUID,
        primaryTabID: UUID? = nil,
        companionTabID: UUID? = nil,
        focusedTabID: UUID? = nil,
        splitRatio: Double = 0.5
    ) {
        self.workspaceID = workspaceID
        self.primaryTabID = primaryTabID
        self.companionTabID = companionTabID
        self.focusedTabID = focusedTabID
        self.splitRatio = min(0.8, max(0.2, splitRatio))
    }
}

public struct TerminalSessionRecord: Codable, Hashable, Sendable {
    public var tabID: UUID
    public var workingDirectory: URL
    public var startupInput: String?
    public var resumeProvider: String?
    public var resumeIdentifier: String?
    public var scrollback: ScrollbackPolicy

    public init(
        tabID: UUID,
        workingDirectory: URL,
        startupInput: String? = nil,
        resumeProvider: String? = nil,
        resumeIdentifier: String? = nil,
        scrollback: ScrollbackPolicy = .limited(lines: 10_000)
    ) {
        self.tabID = tabID
        self.workingDirectory = workingDirectory
        self.startupInput = startupInput
        self.resumeProvider = resumeProvider
        self.resumeIdentifier = resumeIdentifier
        self.scrollback = scrollback
    }
}

public enum ScrollbackPolicy: Codable, Hashable, Sendable {
    case disabled
    case limited(lines: Int)
    case unlimited

    public var ghosttyConfigurationValue: String {
        switch self {
        case .disabled: return "0"
        case .limited(let lines): return String(max(1, lines))
        case .unlimited: return "4294967295"
        }
    }
}

public struct WorkspaceActivitySession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var baselineSnapshotID: UUID?

    public init(id: UUID = UUID(), workspaceID: UUID, startedAt: Date = Date(), endedAt: Date? = nil, baselineSnapshotID: UUID? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.baselineSnapshotID = baselineSnapshotID
    }
}

public enum ReviewBaseline: Hashable, Sendable {
    case head
    case branch(String)
    case activitySessionStart
    case lastCompletedReview
    case snapshot(UUID)

    public var storageValue: String {
        switch self {
        case .head: return "head"
        case .branch(let reference): return "branch:\(reference)"
        case .activitySessionStart: return "activity"
        case .lastCompletedReview: return "last-review"
        case .snapshot(let id): return "snapshot:\(id.uuidString)"
        }
    }

    public init(storageValue: String) {
        if storageValue.hasPrefix("branch:") { self = .branch(String(storageValue.dropFirst(7))) }
        else if storageValue == "activity" { self = .activitySessionStart }
        else if storageValue == "last-review" { self = .lastCompletedReview }
        else if storageValue.hasPrefix("snapshot:"), let id = UUID(uuidString: String(storageValue.dropFirst(9))) { self = .snapshot(id) }
        else { self = .head }
    }
}

public enum ReviewDisplayMode: String, Codable, CaseIterable, Hashable, Sendable {
    case unified
    case split
    case fullFile
}

public struct ReviewSessionRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var activitySessionID: UUID
    public var startedAt: Date
    public var completedAt: Date?
    public var finalSnapshotID: UUID?

    public init(id: UUID = UUID(), workspaceID: UUID, activitySessionID: UUID, startedAt: Date = Date(), completedAt: Date? = nil, finalSnapshotID: UUID? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.activitySessionID = activitySessionID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.finalSnapshotID = finalSnapshotID
    }
}

public struct ReviewSnapshotRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var activitySessionID: UUID
    public var reviewSessionID: UUID?
    public var fingerprint: String
    public var reason: String
    public var createdAt: Date
    public var repositories: [ReviewSnapshotRepository]

    public init(id: UUID = UUID(), workspaceID: UUID, activitySessionID: UUID, reviewSessionID: UUID? = nil, fingerprint: String, reason: String, createdAt: Date = Date(), repositories: [ReviewSnapshotRepository]) {
        self.id = id
        self.workspaceID = workspaceID
        self.activitySessionID = activitySessionID
        self.reviewSessionID = reviewSessionID
        self.fingerprint = fingerprint
        self.reason = reason
        self.createdAt = createdAt
        self.repositories = repositories
    }
}

public struct ReviewSnapshotRepository: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { repositoryID }
    public var repositoryID: UUID
    public var headOID: String?
    public var branch: String
    public var files: [SnapshotFile]

    public init(repositoryID: UUID, headOID: String?, branch: String, files: [SnapshotFile]) {
        self.repositoryID = repositoryID
        self.headOID = headOID
        self.branch = branch
        self.files = files
    }
}

public struct SnapshotFile: Codable, Hashable, Sendable {
    public var path: String
    public var status: FileStatus
    public var oldPath: String?
    public var oldContent: String
    public var newContent: String
    public var patch: String
    public var fingerprint: String

    public init(path: String, status: FileStatus, oldPath: String? = nil, oldContent: String, newContent: String, patch: String, fingerprint: String) {
        self.path = path
        self.status = status
        self.oldPath = oldPath
        self.oldContent = oldContent
        self.newContent = newContent
        self.patch = patch
        self.fingerprint = fingerprint
    }
}

public enum AnnotationKind: String, Codable, Sendable { case comment, question }
public enum DiffSide: String, Codable, Hashable, Sendable { case old, new }

public struct ReviewAnnotation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var activitySessionID: UUID
    public var reviewSessionID: UUID
    public var repositoryID: UUID
    public var snapshotID: UUID
    public var kind: AnnotationKind
    public var filePath: String
    public var side: DiffSide
    public var startLine: Int
    public var endLine: Int
    public var anchorFingerprint: String
    public var selectedCode: String
    public var context: String
    public var userText: String
    public var response: String?
    public var createdAt: Date
    public var resolvedAt: Date?
    public var isOutdated: Bool

    public init(id: UUID = UUID(), workspaceID: UUID, activitySessionID: UUID, reviewSessionID: UUID, repositoryID: UUID, snapshotID: UUID, kind: AnnotationKind, filePath: String, side: DiffSide, startLine: Int, endLine: Int, anchorFingerprint: String, selectedCode: String, context: String, userText: String, response: String? = nil, createdAt: Date = Date(), resolvedAt: Date? = nil, isOutdated: Bool = false) {
        self.id = id
        self.workspaceID = workspaceID
        self.activitySessionID = activitySessionID
        self.reviewSessionID = reviewSessionID
        self.repositoryID = repositoryID
        self.snapshotID = snapshotID
        self.kind = kind
        self.filePath = filePath
        self.side = side
        self.startLine = startLine
        self.endLine = endLine
        self.anchorFingerprint = anchorFingerprint
        self.selectedCode = selectedCode
        self.context = context
        self.userText = userText
        self.response = response
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.isOutdated = isOutdated
    }
}

public enum AssistantProvider: String, Codable, CaseIterable, Sendable { case codex, copilot }
public enum AssistantMessageRole: String, Codable, Sendable { case user, assistant, error }

public struct AssistantThreadRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var annotationID: UUID
    public var provider: AssistantProvider
    public var providerSessionID: String?
    public var model: String?
    public var createdAt: Date
}

public struct AssistantMessageRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var threadID: UUID
    public var role: AssistantMessageRole
    public var content: String
    public var isStreaming: Bool
    public var errorCode: String?
    public var createdAt: Date
}

public struct NotificationRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var tabID: UUID?
    public var title: String
    public var body: String
    public var createdAt: Date
    public var readAt: Date?
}

public enum RepositoryOperationPhase: String, Codable, Sendable { case idle, cloning, fetching, creatingWorktree, complete, failed }

public struct RepositoryOperationState: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var phase: RepositoryOperationPhase
    public var progress: Double
    public var message: String?

    public init(id: UUID, phase: RepositoryOperationPhase = .idle, progress: Double = 0, message: String? = nil) {
        self.id = id
        self.phase = phase
        self.progress = progress
        self.message = message
    }
}

public struct RepositoryDraft: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var remoteURL: String
    public var cachedSourceID: UUID?
    public var branch: String
    public var baseBranch: String

    public init(id: UUID = UUID(), remoteURL: String = "", cachedSourceID: UUID? = nil, branch: String = "", baseBranch: String = "") {
        self.id = id
        self.remoteURL = remoteURL
        self.cachedSourceID = cachedSourceID
        self.branch = branch
        self.baseBranch = baseBranch
    }
}

public struct WorkspaceReviewState: Sendable {
    public var workspaceID: UUID
    public var baseline: ReviewBaseline
    public var mode: ReviewDisplayMode
    public var repositoryFilter: UUID?
    public var files: [WorkspaceFileDiff]
    public var snapshot: ReviewSnapshotRecord?
    public var annotations: [ReviewAnnotation]
    public var historicalSnapshots: [ReviewSnapshotRecord]
    public var repositoryErrors: [UUID: String]
    public var isRefreshing: Bool
    public var errorMessage: String?

    public init(workspaceID: UUID, baseline: ReviewBaseline = .head, mode: ReviewDisplayMode = .unified, repositoryFilter: UUID? = nil, files: [WorkspaceFileDiff] = [], snapshot: ReviewSnapshotRecord? = nil, annotations: [ReviewAnnotation] = [], historicalSnapshots: [ReviewSnapshotRecord] = [], repositoryErrors: [UUID: String] = [:], isRefreshing: Bool = false, errorMessage: String? = nil) {
        self.workspaceID = workspaceID
        self.baseline = baseline
        self.mode = mode
        self.repositoryFilter = repositoryFilter
        self.files = files
        self.snapshot = snapshot
        self.annotations = annotations
        self.historicalSnapshots = historicalSnapshots
        self.repositoryErrors = repositoryErrors
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
    }

    public var additions: Int { files.reduce(0) { $0 + $1.diff.addedLineCount } }
    public var deletions: Int { files.reduce(0) { $0 + $1.diff.removedLineCount } }
}

public struct WorkspaceFileDiff: Identifiable, Hashable, Sendable {
    public var id: String { "\(repositoryID.uuidString):\(diff.path)" }
    public var repositoryID: UUID
    public var repositoryName: String
    public var diff: FileDiff
    public var oldContent: String
    public var newContent: String
}
