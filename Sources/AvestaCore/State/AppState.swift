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
    public var isBoardVisible: Bool

    public init(
        workspaces: [Workspace] = [],
        activeWorkspaceID: UUID? = nil,
        globalBoard: BoardStore? = nil,
        config: AppConfig = .default,
        cachedRepos: [CachedRepo] = [],
        notificationBadges: [UUID: Int] = [:],
        isBoardVisible: Bool = false
    ) {
        self.workspaces = workspaces
        self.activeWorkspaceID = activeWorkspaceID
        self.globalBoard = globalBoard ?? BoardStore()
        self.config = config
        self.cachedRepos = cachedRepos
        self.notificationBadges = notificationBadges
        self.isBoardVisible = isBoardVisible
    }

    public var activeWorkspace: Workspace? {
        get {
            guard let activeWorkspaceID else { return workspaces.first }
            return workspaces.first { $0.id == activeWorkspaceID }
        }
        set {
            activeWorkspaceID = newValue?.id
        }
    }

    public func createWorkspace(name: String) {
        let path = config.workspacesRoot.appending(path: name, directoryHint: .isDirectory)
        let workspace = Workspace(name: name, path: path)
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
    }

    public func incrementBadge(for tabID: UUID) {
        notificationBadges[tabID, default: 0] += 1
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
}
