import Foundation
import Observation

@Observable
@MainActor
public final class TerminalTabModel: WorkspaceTab {
    public let id: UUID
    public var title: String
    public let kind: TabKind = .terminal
    public let isClosable: Bool = true
    public var workingDirectory: URL
    public var isProcessRunning: Bool
    public var pendingPaste: String?

    public init(
        id: UUID = UUID(),
        title: String = "Terminal",
        workingDirectory: URL,
        isProcessRunning: Bool = true
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.isProcessRunning = isProcessRunning
    }
}
