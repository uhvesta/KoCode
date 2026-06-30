import Foundation

public struct OutputMatch: Hashable, Sendable {
    public let pattern: String
    public let line: String
}

public final class OutputMonitor: @unchecked Sendable {
    private let patterns: [String]
    private var buffer = ""

    public init(patterns: [String]) {
        self.patterns = patterns
    }

    public func ingest(_ text: String) -> [OutputMatch] {
        buffer += text
        var outputMatches: [OutputMatch] = []

        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            outputMatches.append(contentsOf: matches(in: line))
        }

        return outputMatches
    }

    private func matches(in line: String) -> [OutputMatch] {
        patterns.compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard regex.firstMatch(in: line, range: range) != nil else { return nil }
            return OutputMatch(pattern: pattern, line: line)
        }
    }
}
