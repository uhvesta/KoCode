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
    public var outputBuffer: String
    public var resume: TerminalResumeSnapshot?

    public init(
        id: UUID = UUID(),
        title: String = "Terminal",
        workingDirectory: URL,
        isProcessRunning: Bool = true,
        outputBuffer: String = "",
        resume: TerminalResumeSnapshot? = nil
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.isProcessRunning = isProcessRunning
        self.outputBuffer = outputBuffer
        self.resume = resume
    }

    public func appendOutput(_ output: String) {
        outputBuffer += output
        if outputBuffer.count > 50_000 {
            outputBuffer.removeFirst(outputBuffer.count - 50_000)
        }
    }
}
