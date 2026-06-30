import Foundation
import Observation

@Observable
@MainActor
public final class CodeReviewTabModel: WorkspaceTab {
    public let id: UUID
    public var title: String
    public let kind: TabKind = .codeReview
    public let isClosable: Bool = true
    public var session: CodeReviewSession?

    public init(
        id: UUID = UUID(),
        title: String = "Code Review",
        session: CodeReviewSession? = nil
    ) {
        self.id = id
        self.title = title
        self.session = session
    }
}
