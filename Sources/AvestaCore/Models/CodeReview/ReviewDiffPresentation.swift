import Foundation

/// A side-aware, non-durable representation shared by every review mode.
/// It is deliberately derived only from `FileDiff.hunks`; views must not infer
/// change kinds by comparing the two source strings independently.
public struct ReviewDiffDocument: Hashable, Sendable {
    public let file: WorkspaceFileDiff
    /// Nil means every representation was requested. Production views pass
    /// their active mode so large files do not eagerly build invisible rows.
    public let presentationMode: ReviewDisplayMode?
    public let hunks: [ReviewDiffHunk]
    public let oldLines: [String]
    public let newLines: [String]
    public let changedOldLines: Set<Int>
    public let changedNewLines: Set<Int>
    public let fullFileRows: [FullFileDiffRow]
    public let displayedFullFileSide: DiffSide

    public init(file: WorkspaceFileDiff, mode: ReviewDisplayMode? = nil) {
        self.file = file
        presentationMode = mode
        oldLines = Self.sourceLines(file.oldContent)
        newLines = Self.sourceLines(file.newContent)
        hunks = file.diff.hunks.enumerated().map {
            ReviewDiffHunk(
                hunk: $0.element,
                ordinal: $0.offset,
                buildSplitRows: mode == nil || mode == .split
            )
        }
        changedOldLines = Set(file.diff.hunks.flatMap(\.lines).compactMap { $0.kind == .removed ? $0.oldLineNumber : nil })
        changedNewLines = Set(file.diff.hunks.flatMap(\.lines).compactMap { $0.kind == .added ? $0.newLineNumber : nil })
        displayedFullFileSide = file.diff.status == .deleted ? .old : .new
        if mode == nil || mode == .fullFile {
            fullFileRows = Self.buildFullFileRows(
                file: file,
                oldLines: oldLines,
                newLines: newLines,
                changedOldLines: changedOldLines,
                changedNewLines: changedNewLines
            )
        } else {
            fullFileRows = []
        }
    }

    public var firstHunkID: String? { hunks.first?.id }

    public func sourceExcerpt(side: DiffSide, lines: ClosedRange<Int>) -> String {
        let source = side == .old ? oldLines : newLines
        guard !source.isEmpty else { return "" }
        let lower = max(1, lines.lowerBound)
        let upper = min(source.count, lines.upperBound)
        guard lower <= upper else { return "" }
        return source[(lower - 1)...(upper - 1)].joined(separator: "\n")
    }

    public func surroundingContext(side: DiffSide, lines: ClosedRange<Int>, padding: Int = 3) -> String {
        let source = side == .old ? oldLines : newLines
        guard !source.isEmpty else { return "" }
        let lower = max(1, lines.lowerBound - max(0, padding))
        let upper = min(source.count, lines.upperBound + max(0, padding))
        guard lower <= upper else { return "" }
        return source[(lower - 1)...(upper - 1)].enumerated().map {
            "\(lower + $0.offset)  \($0.element)"
        }.joined(separator: "\n")
    }

    public func hunkID(side: DiffSide, intersecting lines: ClosedRange<Int>) -> String? {
        hunks.first { hunk in
            hunk.unifiedRows.contains { row in
                let lineNumber = side == .old ? row.line.oldLineNumber : row.line.newLineNumber
                return lineNumber.map(lines.contains) == true
            }
        }?.id
    }

    public func fullFileTargetID(forHunkID hunkID: String) -> String? {
        guard let hunk = hunks.first(where: { $0.id == hunkID }) else { return nil }
        if displayedFullFileSide == .old { return "old:\(max(1, hunk.oldStart))" }
        if let firstAdded = hunk.unifiedRows.lazy.filter({ $0.line.kind == .added }).compactMap({ $0.line.newLineNumber }).first {
            return "new:\(firstAdded)"
        }
        return fullFileRows.compactMap { row -> FullFileDeletionMarker? in
            guard case .deletion(let marker) = row else { return nil }
            return marker
        }.first(where: { $0.oldStartLine >= hunk.oldStart && $0.oldStartLine < hunk.oldStart + max(1, hunk.oldCount) })?.id
    }

    private static func sourceLines(_ source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func buildFullFileRows(
        file: WorkspaceFileDiff,
        oldLines: [String],
        newLines: [String],
        changedOldLines: Set<Int>,
        changedNewLines: Set<Int>
    ) -> [FullFileDiffRow] {
        if file.diff.status == .deleted {
            return oldLines.enumerated().map { index, content in
                .source(FullFileSourceRow(
                    id: "old:\(index + 1)",
                    side: .old,
                    lineNumber: index + 1,
                    kind: changedOldLines.contains(index + 1) ? .removed : .context,
                    content: content
                ))
            }
        }

        var deletionMarkers: [Int: [FullFileDeletionMarker]] = [:]
        for (hunkIndex, hunk) in file.diff.hunks.enumerated() {
            var newCursor = hunk.newStart
            var index = 0
            while index < hunk.lines.count {
                let line = hunk.lines[index]
                if line.kind == .context {
                    newCursor = (line.newLineNumber ?? newCursor) + 1
                    index += 1
                    continue
                }

                var removed: [DiffLine] = []
                var added: [DiffLine] = []
                while index < hunk.lines.count, hunk.lines[index].kind != .context {
                    let change = hunk.lines[index]
                    if change.kind == .removed { removed.append(change) }
                    if change.kind == .added {
                        added.append(change)
                        newCursor = (change.newLineNumber ?? newCursor) + 1
                    }
                    index += 1
                }

                if !removed.isEmpty && added.isEmpty {
                    let insertionLine = max(1, newCursor)
                    let identity = "deletion:\(hunkIndex):\(removed.first?.oldLineNumber ?? 0):\(removed.count)"
                    deletionMarkers[insertionLine, default: []].append(
                        FullFileDeletionMarker(
                            id: identity,
                            insertionLine: insertionLine,
                            removedLineCount: removed.count,
                            oldStartLine: removed.first?.oldLineNumber ?? hunk.oldStart,
                            removedLines: removed.map(\.content)
                        )
                    )
                }
            }
        }

        var rows: [FullFileDiffRow] = []
        for (index, content) in newLines.enumerated() {
            let lineNumber = index + 1
            rows.append(contentsOf: (deletionMarkers[lineNumber] ?? []).map(FullFileDiffRow.deletion))
            rows.append(.source(FullFileSourceRow(
                id: "new:\(lineNumber)",
                side: .new,
                lineNumber: lineNumber,
                kind: changedNewLines.contains(lineNumber) ? .added : .context,
                content: content
            )))
        }
        rows.append(contentsOf: (deletionMarkers[newLines.count + 1] ?? []).map(FullFileDiffRow.deletion))
        return rows
    }
}

/// A GitHub-style, side-aware line range. `anchorLine` is the first click and
/// `focusLine` is the most recent Shift-click, so the selection can grow in
/// either direction while persistence always receives normalized bounds.
public struct ReviewLineSelection: Hashable, Sendable {
    public let fileID: String
    public let side: DiffSide
    public let anchorLine: Int
    public let focusLine: Int

    public init(fileID: String, side: DiffSide, anchorLine: Int, focusLine: Int? = nil) {
        self.fileID = fileID
        self.side = side
        self.anchorLine = max(1, anchorLine)
        self.focusLine = max(1, focusLine ?? anchorLine)
    }

    public var lines: ClosedRange<Int> {
        min(anchorLine, focusLine)...max(anchorLine, focusLine)
    }

    public var lineCount: Int { lines.upperBound - lines.lowerBound + 1 }

    public func contains(fileID: String, side: DiffSide, line: Int) -> Bool {
        self.fileID == fileID && self.side == side && lines.contains(line)
    }

    public func extending(to line: Int) -> ReviewLineSelection {
        ReviewLineSelection(fileID: fileID, side: side, anchorLine: anchorLine, focusLine: line)
    }

    /// Applies the same click semantics as a GitHub review: a normal click
    /// starts a new selection, while Shift-click extends only a selection on
    /// the same file and side. Crossing files or diff sides starts over.
    public static func selectionAfterClick(
        current: ReviewLineSelection?,
        fileID: String,
        side: DiffSide,
        line: Int,
        extending: Bool
    ) -> ReviewLineSelection {
        if extending,
           let current,
           current.fileID == fileID,
           current.side == side {
            return current.extending(to: line)
        }
        return ReviewLineSelection(fileID: fileID, side: side, anchorLine: line)
    }
}

public struct ReviewDiffHunk: Identifiable, Hashable, Sendable {
    public let id: String
    public let ordinal: Int
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let unifiedRows: [UnifiedDiffRow]
    public let splitRows: [SplitDiffRow]

    init(hunk: DiffHunk, ordinal: Int, buildSplitRows: Bool = true) {
        self.ordinal = ordinal
        oldStart = hunk.oldStart
        oldCount = hunk.oldCount
        newStart = hunk.newStart
        newCount = hunk.newCount
        id = Self.stableID(for: hunk, ordinal: ordinal)
        unifiedRows = hunk.lines.enumerated().map { lineIndex, line in
            UnifiedDiffRow(
                id: "u:\(ordinal):\(lineIndex):\(line.oldLineNumber ?? 0):\(line.newLineNumber ?? 0):\(line.kind.rawValue)",
                line: line,
                sourceSide: line.kind == .removed ? .old : .new,
                sourceLineNumber: line.kind == .removed ? line.oldLineNumber : line.newLineNumber
            )
        }
        splitRows = buildSplitRows ? Self.buildSplitRows(hunk.lines, hunkOrdinal: ordinal) : []
    }

    public var header: String { "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" }

    /// Produces the navigation identity without constructing every derived
    /// row in the document. Workspace-level hunk navigation uses this path so
    /// a SwiftUI body update remains proportional to the number of hunks, not
    /// the number of lines in every changed file.
    public static func stableID(for hunk: DiffHunk, ordinal: Int) -> String {
        "h:\(ordinal):\(hunk.oldStart):\(hunk.oldCount):\(hunk.newStart):\(hunk.newCount)"
    }

    private static func buildSplitRows(_ lines: [DiffLine], hunkOrdinal: Int) -> [SplitDiffRow] {
        var result: [SplitDiffRow] = []
        var index = 0
        var group = 0

        while index < lines.count {
            let line = lines[index]
            if line.kind == .context {
                result.append(SplitDiffRow(
                    id: "s:\(hunkOrdinal):context:\(line.oldLineNumber ?? 0):\(line.newLineNumber ?? 0)",
                    changeGroupID: nil,
                    old: DiffCell(line: line, side: .old),
                    new: DiffCell(line: line, side: .new)
                ))
                index += 1
                continue
            }

            var removed: [DiffLine] = []
            var added: [DiffLine] = []
            while index < lines.count, lines[index].kind != .context {
                if lines[index].kind == .removed { removed.append(lines[index]) }
                if lines[index].kind == .added { added.append(lines[index]) }
                index += 1
            }

            let groupID = "g:\(hunkOrdinal):\(group)"
            for rowIndex in 0..<max(removed.count, added.count) {
                result.append(SplitDiffRow(
                    id: "s:\(hunkOrdinal):\(group):\(rowIndex)",
                    changeGroupID: groupID,
                    old: removed.indices.contains(rowIndex) ? DiffCell(line: removed[rowIndex], side: .old) : nil,
                    new: added.indices.contains(rowIndex) ? DiffCell(line: added[rowIndex], side: .new) : nil
                ))
            }
            group += 1
        }
        return result
    }
}

/// Precomputes inline-annotation membership once per selected file. Review
/// rows can then look up their comments in O(1), instead of scanning every
/// annotation during each SwiftUI body update and scroll pass.
public struct ReviewAnnotationIndex: Sendable {
    private struct Key: Hashable, Sendable {
        let side: DiffSide
        let line: Int
    }

    private let annotationsByLine: [Key: [ReviewAnnotation]]

    public init(annotations: [ReviewAnnotation]) {
        var values: [Key: [ReviewAnnotation]] = [:]
        for annotation in annotations {
            let lower = max(1, min(annotation.startLine, annotation.endLine))
            let upper = max(1, max(annotation.startLine, annotation.endLine))
            for line in lower...upper {
                values[Key(side: annotation.side, line: line), default: []].append(annotation)
            }
        }
        annotationsByLine = values
    }

    public func annotations(side: DiffSide, line: Int) -> [ReviewAnnotation] {
        annotationsByLine[Key(side: side, line: line)] ?? []
    }

    public func count(side: DiffSide, line: Int) -> Int {
        annotationsByLine[Key(side: side, line: line)]?.count ?? 0
    }
}

public struct UnifiedDiffRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let line: DiffLine
    public let sourceSide: DiffSide
    public let sourceLineNumber: Int?
}

public struct SplitDiffRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let changeGroupID: String?
    public let old: DiffCell?
    public let new: DiffCell?
}

public struct DiffCell: Hashable, Sendable {
    public let side: DiffSide
    public let lineNumber: Int
    public let kind: DiffLineKind
    public let sourceLineIndex: Int
    public let content: String

    init?(line: DiffLine, side: DiffSide) {
        let number = side == .old ? line.oldLineNumber : line.newLineNumber
        guard let number else { return nil }
        self.side = side
        lineNumber = number
        kind = line.kind
        sourceLineIndex = number - 1
        content = line.content
    }

    public var diffLine: DiffLine {
        DiffLine(
            kind: kind,
            oldLineNumber: side == .old ? lineNumber : nil,
            newLineNumber: side == .new ? lineNumber : nil,
            content: content
        )
    }
}

public enum FullFileDiffRow: Identifiable, Hashable, Sendable {
    case source(FullFileSourceRow)
    case deletion(FullFileDeletionMarker)

    public var id: String {
        switch self {
        case .source(let row): return row.id
        case .deletion(let marker): return marker.id
        }
    }
}

public struct FullFileSourceRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let side: DiffSide
    public let lineNumber: Int
    public let kind: DiffLineKind
    public let content: String

    public init(id: String, side: DiffSide, lineNumber: Int, kind: DiffLineKind, content: String) {
        self.id = id
        self.side = side
        self.lineNumber = lineNumber
        self.kind = kind
        self.content = content
    }

    public var diffLine: DiffLine {
        DiffLine(
            kind: kind,
            oldLineNumber: side == .old ? lineNumber : nil,
            newLineNumber: side == .new ? lineNumber : nil,
            content: content
        )
    }
}

public struct FullFileDeletionMarker: Identifiable, Hashable, Sendable {
    public let id: String
    public let insertionLine: Int
    public let removedLineCount: Int
    public let oldStartLine: Int
    public let removedLines: [String]
}
