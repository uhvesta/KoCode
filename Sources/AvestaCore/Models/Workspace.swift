import Foundation
import Observation

@Observable
@MainActor
public final class Workspace: Identifiable {
    public let id: UUID
    public var name: String
    public var path: URL
    public var repos: [WorktreeRef]
    public var tabs: [any WorkspaceTab]
    public var activeTabID: UUID?
    public var board: BoardStore

    public init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        repos: [WorktreeRef] = [],
        tabs: [any WorkspaceTab] = [],
        activeTabID: UUID? = nil,
        board: BoardStore? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.repos = repos
        self.tabs = tabs
        self.activeTabID = activeTabID
        self.board = board ?? BoardStore()

        if tabs.isEmpty {
            let terminal = TerminalTabModel(workingDirectory: path)
            self.tabs = [terminal]
            self.activeTabID = terminal.id
        } else if activeTabID == nil {
            self.activeTabID = tabs.first?.id
        }
    }

    public var activeTab: (any WorkspaceTab)? {
        guard let activeTabID else { return tabs.first }
        return tabs.first { $0.id == activeTabID }
    }

    public func addTerminalTab() {
        let tab = TerminalTabModel(workingDirectory: path)
        tabs.append(tab)
        activeTabID = tab.id
    }

    public func addCodeReviewTab(session: CodeReviewSession? = nil) {
        let tab = CodeReviewTabModel(session: session)
        tabs.append(tab)
        activeTabID = tab.id
    }

    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].isClosable else { return }
        tabs.remove(at: index)
        if activeTabID == id {
            activeTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
    }
}
