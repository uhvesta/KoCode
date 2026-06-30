import Foundation
import Observation

@Observable
@MainActor
public final class BoardStore {
    public var items: [BoardItem]

    public init(items: [BoardItem] = []) {
        self.items = items
    }

    public func send(_ content: String, source: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(BoardItem(content: trimmed, source: source), at: 0)
    }

    public func paste() -> BoardItem? {
        items.first
    }
}

public struct BoardItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let content: String
    public let source: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        source: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.createdAt = createdAt
    }
}
