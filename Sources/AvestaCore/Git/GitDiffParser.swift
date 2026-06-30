import Foundation

public struct GitDiffParser: Sendable {
    public init() {}

    public func parse(_ diff: String) throws -> [FileDiff] {
        var files: [FileDiff] = []
        var builder: FileBuilder?

        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("diff --git ") {
                if let file = builder?.build() {
                    files.append(file)
                }
                builder = FileBuilder(diffHeader: rawLine)
                continue
            }

            guard builder != nil else { continue }
            try builder?.consume(rawLine)
        }

        if let file = builder?.build() {
            files.append(file)
        }

        return files
    }
}

private struct FileBuilder {
    var path: String
    var oldPath: String?
    var status: FileStatus = .modified
    var hunks: [DiffHunk] = []

    private var oldHeaderPath: String?
    private var newHeaderPath: String?
    private var currentHunk: HunkBuilder?

    init(diffHeader: String) {
        let pair = Self.parseDiffHeader(diffHeader)
        self.oldPath = pair.old
        self.path = pair.new
    }

    mutating func consume(_ line: String) throws {
        if line.hasPrefix("new file mode") {
            status = .added
            return
        }
        if line.hasPrefix("deleted file mode") {
            status = .deleted
            return
        }
        if line.hasPrefix("rename from ") {
            oldPath = String(line.dropFirst("rename from ".count))
            status = .renamed
            return
        }
        if line.hasPrefix("rename to ") {
            path = String(line.dropFirst("rename to ".count))
            status = .renamed
            return
        }
        if line.hasPrefix("--- ") {
            oldHeaderPath = Self.cleanPath(String(line.dropFirst(4)))
            return
        }
        if line.hasPrefix("+++ ") {
            newHeaderPath = Self.cleanPath(String(line.dropFirst(4)))
            if newHeaderPath != "/dev/null" {
                path = newHeaderPath ?? path
            }
            if oldHeaderPath == "/dev/null" {
                status = .added
            } else if newHeaderPath == "/dev/null" {
                status = .deleted
            }
            return
        }
        if line.hasPrefix("@@ ") {
            flushHunk()
            currentHunk = try HunkBuilder(header: line)
            return
        }

        if currentHunk != nil {
            currentHunk?.consume(line)
        }
    }

    mutating func build() -> FileDiff? {
        flushHunk()
        guard !path.isEmpty else { return nil }
        return FileDiff(path: path, oldPath: oldPath == path ? nil : oldPath, status: status, hunks: hunks)
    }

    private mutating func flushHunk() {
        if let hunk = currentHunk?.build() {
            hunks.append(hunk)
        }
        currentHunk = nil
    }

    private static func parseDiffHeader(_ header: String) -> (old: String?, new: String) {
        let prefix = "diff --git "
        let rest = header.hasPrefix(prefix) ? String(header.dropFirst(prefix.count)) : header
        let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
        let old = parts.first.map(cleanPath)
        let new = parts.dropFirst().first.map(cleanPath) ?? old ?? ""
        return (old, new)
    }

    private static func cleanPath(_ raw: String) -> String {
        if raw == "/dev/null" { return raw }
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("a/") || value.hasPrefix("b/") {
            value.removeFirst(2)
        }
        return value
    }
}

private struct HunkBuilder {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    var lines: [DiffLine] = []

    private var nextOldLine: Int
    private var nextNewLine: Int

    init(header: String) throws {
        let ranges = try Self.parseHeader(header)
        oldStart = ranges.oldStart
        oldCount = ranges.oldCount
        newStart = ranges.newStart
        newCount = ranges.newCount
        nextOldLine = ranges.oldStart
        nextNewLine = ranges.newStart
    }

    mutating func consume(_ line: String) {
        guard let marker = line.first else { return }
        let content = String(line.dropFirst())

        switch marker {
        case " ":
            lines.append(DiffLine(kind: .context, oldLineNumber: nextOldLine, newLineNumber: nextNewLine, content: content))
            nextOldLine += 1
            nextNewLine += 1
        case "+":
            lines.append(DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: nextNewLine, content: content))
            nextNewLine += 1
        case "-":
            lines.append(DiffLine(kind: .removed, oldLineNumber: nextOldLine, newLineNumber: nil, content: content))
            nextOldLine += 1
        case "\\":
            break
        default:
            lines.append(DiffLine(kind: .context, oldLineNumber: nextOldLine, newLineNumber: nextNewLine, content: line))
            nextOldLine += 1
            nextNewLine += 1
        }
    }

    func build() -> DiffHunk {
        DiffHunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: lines)
    }

    private static func parseHeader(_ header: String) throws -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(header.startIndex..<header.endIndex, in: header)
        guard let match = regex.firstMatch(in: header, range: range) else {
            throw GitDiffParserError.invalidHunkHeader(header)
        }

        func int(at index: Int, default defaultValue: Int) -> Int {
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound, let range = Range(matchRange, in: header) else {
                return defaultValue
            }
            return Int(header[range]) ?? defaultValue
        }

        return (int(at: 1, default: 0), int(at: 2, default: 1), int(at: 3, default: 0), int(at: 4, default: 1))
    }
}

public enum GitDiffParserError: Error, Equatable, LocalizedError {
    case invalidHunkHeader(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHunkHeader(let header):
            return "Invalid unified diff hunk header: \(header)"
        }
    }
}
