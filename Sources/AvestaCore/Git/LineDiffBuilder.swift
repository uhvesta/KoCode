import Foundation

/// Builds conventional, context-limited hunks for comparisons that do not
/// originate from a Git patch (for example snapshot-to-snapshot review).
enum LineDiffBuilder {
    static func build(
        path: String,
        oldPath: String? = nil,
        status: FileStatus,
        oldContent: String,
        newContent: String,
        context: Int = 3
    ) -> FileDiff {
        let oldLines = sourceLines(oldContent)
        let newLines = sourceLines(newContent)
        let difference = newLines.difference(from: oldLines)
        var removals: Set<Int> = []
        var insertions: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }

        var operations: [Operation] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removals.contains(oldIndex) {
                operations.append(Operation(
                    line: DiffLine(kind: .removed, oldLineNumber: oldIndex + 1, newLineNumber: nil, content: oldLines[oldIndex]),
                    oldCursor: oldIndex + 1,
                    newCursor: newIndex + 1
                ))
                oldIndex += 1
            } else if newIndex < newLines.count, insertions.contains(newIndex) {
                operations.append(Operation(
                    line: DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: newIndex + 1, content: newLines[newIndex]),
                    oldCursor: oldIndex + 1,
                    newCursor: newIndex + 1
                ))
                newIndex += 1
            } else if oldIndex < oldLines.count, newIndex < newLines.count {
                operations.append(Operation(
                    line: DiffLine(kind: .context, oldLineNumber: oldIndex + 1, newLineNumber: newIndex + 1, content: newLines[newIndex]),
                    oldCursor: oldIndex + 1,
                    newCursor: newIndex + 1
                ))
                oldIndex += 1
                newIndex += 1
            } else if oldIndex < oldLines.count {
                operations.append(Operation(
                    line: DiffLine(kind: .removed, oldLineNumber: oldIndex + 1, newLineNumber: nil, content: oldLines[oldIndex]),
                    oldCursor: oldIndex + 1,
                    newCursor: newIndex + 1
                ))
                oldIndex += 1
            } else {
                operations.append(Operation(
                    line: DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: newIndex + 1, content: newLines[newIndex]),
                    oldCursor: oldIndex + 1,
                    newCursor: newIndex + 1
                ))
                newIndex += 1
            }
        }

        let changed = operations.indices.filter { operations[$0].line.kind != .context }
        guard !changed.isEmpty else { return FileDiff(path: path, oldPath: oldPath, status: status, hunks: []) }

        var ranges: [ClosedRange<Int>] = []
        for index in changed {
            let candidate = max(0, index - context)...min(operations.count - 1, index + context)
            if let previous = ranges.last, candidate.lowerBound <= previous.upperBound + 1 {
                ranges[ranges.count - 1] = previous.lowerBound...max(previous.upperBound, candidate.upperBound)
            } else {
                ranges.append(candidate)
            }
        }

        let hunks = ranges.map { range -> DiffHunk in
            let slice = operations[range]
            let oldCount = slice.reduce(0) { $0 + ($1.line.kind == .added ? 0 : 1) }
            let newCount = slice.reduce(0) { $0 + ($1.line.kind == .removed ? 0 : 1) }
            return DiffHunk(
                oldStart: oldLines.isEmpty ? 0 : slice.first!.oldCursor,
                oldCount: oldCount,
                newStart: newLines.isEmpty ? 0 : slice.first!.newCursor,
                newCount: newCount,
                lines: slice.map(\.line)
            )
        }
        return FileDiff(path: path, oldPath: oldPath, status: status, hunks: hunks)
    }

    private static func sourceLines(_ source: String) -> [String] {
        guard !source.isEmpty else { return [] }
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if source.hasSuffix("\n"), lines.last == "" { lines.removeLast() }
        return lines
    }

    private struct Operation {
        let line: DiffLine
        let oldCursor: Int
        let newCursor: Int
    }
}
