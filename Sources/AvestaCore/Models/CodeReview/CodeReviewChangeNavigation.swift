import Foundation

public struct CodeReviewChangeRange: Codable, Equatable, Hashable, Sendable {
    public var startLine: Int
    public var endLine: Int

    public init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }
}

public struct CodeReviewNavigationState: Equatable, Sendable {
    public var changes: [CodeReviewChangeRange]
    public var focusedChangeIndex: Int

    public init(changes: [CodeReviewChangeRange], focusedChangeIndex: Int = 0) {
        self.changes = changes
        self.focusedChangeIndex = min(max(focusedChangeIndex, 0), max(changes.count - 1, 0))
    }

    public var focusedChange: CodeReviewChangeRange? {
        guard changes.indices.contains(focusedChangeIndex) else { return nil }
        return changes[focusedChangeIndex]
    }

    public var statusText: String {
        guard !changes.isEmpty else { return "No changes in file" }
        return "Change \(focusedChangeIndex + 1) of \(changes.count)"
    }
}

public enum CodeReviewNavigationAction: Equatable, Sendable {
    case previousChange
    case nextChange
    case focusChange(Int)
}

public enum CodeReviewChangeNavigation {
    public static func reduce(
        state: inout CodeReviewNavigationState,
        action: CodeReviewNavigationAction
    ) {
        switch action {
        case .previousChange:
            state.focusedChangeIndex = max(0, state.focusedChangeIndex - 1)
        case .nextChange:
            state.focusedChangeIndex = min(max(state.changes.count - 1, 0), state.focusedChangeIndex + 1)
        case .focusChange(let index):
            state.focusedChangeIndex = min(max(index, 0), max(state.changes.count - 1, 0))
        }
    }

    public static func changes(in file: FileDiff) -> [CodeReviewChangeRange] {
        let changedLineNumbers = file.hunks
            .flatMap(\.lines)
            .compactMap { line -> Int? in
                guard line.kind != .context else { return nil }
                return line.newLineNumber
            }
            .sorted()

        guard let first = changedLineNumbers.first else { return [] }

        var ranges: [CodeReviewChangeRange] = []
        var start = first
        var previous = first

        for number in changedLineNumbers.dropFirst() {
            if number == previous + 1 {
                previous = number
            } else {
                ranges.append(CodeReviewChangeRange(startLine: start, endLine: previous))
                start = number
                previous = number
            }
        }

        ranges.append(CodeReviewChangeRange(startLine: start, endLine: previous))
        return ranges
    }
}
