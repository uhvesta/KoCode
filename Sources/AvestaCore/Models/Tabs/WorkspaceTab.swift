import Foundation
import Observation

public enum TabKind: String, Codable, CaseIterable, Sendable {
    case terminal
    case codeReview
}

@MainActor
public protocol WorkspaceTab: AnyObject, Identifiable, Observable {
    var id: UUID { get }
    var title: String { get set }
    var kind: TabKind { get }
    var isClosable: Bool { get }
}
