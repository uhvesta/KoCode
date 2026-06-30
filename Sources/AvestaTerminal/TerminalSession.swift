import AvestaCore
import Foundation
import Observation

@Observable
@MainActor
public final class TerminalSession {
    public let id: UUID
    public let tabModel: TerminalTabModel
    public var outputBuffer: String

    public init(id: UUID = UUID(), tabModel: TerminalTabModel, outputBuffer: String = "") {
        self.id = id
        self.tabModel = tabModel
        self.outputBuffer = outputBuffer
    }

    public func appendOutput(_ output: String) {
        outputBuffer += output
    }
}
