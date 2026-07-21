import XCTest
@testable import AvestaCore

final class ReviewDiffPresentationTests: XCTestCase {
    func testUnifiedRowsPreserveSideAndLineNumbers() {
        let document = ReviewDiffDocument(file: fixture(lines: [
            line(.context, 10, 20, "same"),
            line(.removed, 11, nil, "old"),
            line(.added, nil, 21, "new")
        ]))

        let rows = document.hunks[0].unifiedRows
        XCTAssertEqual(rows.map(\.line.kind), [.context, .removed, .added])
        XCTAssertEqual(rows.map(\.sourceSide), [.new, .old, .new])
        XCTAssertEqual(rows.map(\.sourceLineNumber), [20, 11, 21])
    }

    func testSplitPairsReplacementAndUsesFillersForUnequalSides() {
        let document = ReviewDiffDocument(file: fixture(lines: [
            line(.context, 1, 1, "before"),
            line(.removed, 2, nil, "old one"),
            line(.added, nil, 2, "new one"),
            line(.added, nil, 3, "new two"),
            line(.context, 3, 4, "after")
        ]))

        let rows = document.hunks[0].splitRows
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].old?.kind, .context)
        XCTAssertEqual(rows[0].new?.kind, .context)
        XCTAssertEqual(rows[0].old?.side, .old)
        XCTAssertEqual(rows[0].new?.side, .new)
        XCTAssertEqual(rows[0].old?.diffLine.oldLineNumber, 1)
        XCTAssertEqual(rows[0].new?.diffLine.newLineNumber, 1)
        XCTAssertEqual(rows[1].old?.content, "old one")
        XCTAssertEqual(rows[1].new?.content, "new one")
        XCTAssertNil(rows[2].old)
        XCTAssertEqual(rows[2].new?.content, "new two")
        XCTAssertEqual(rows[3].old?.content, "after")
        XCTAssertEqual(rows[3].new?.content, "after")
    }

    func testSplitHandlesManyToOnePureInsertionAndPureDeletion() {
        let replacement = ReviewDiffDocument(file: fixture(lines: [
            line(.removed, 1, nil, "a"), line(.removed, 2, nil, "b"), line(.added, nil, 1, "c")
        ])).hunks[0].splitRows
        XCTAssertEqual(replacement.count, 2)
        XCTAssertEqual(replacement[0].old?.content, "a")
        XCTAssertEqual(replacement[0].new?.content, "c")
        XCTAssertEqual(replacement[1].old?.content, "b")
        XCTAssertNil(replacement[1].new)

        let insertion = ReviewDiffDocument(file: fixture(lines: [line(.added, nil, 1, "new")])).hunks[0].splitRows
        XCTAssertNil(insertion[0].old)
        XCTAssertEqual(insertion[0].new?.kind, .added)

        let deletion = ReviewDiffDocument(file: fixture(lines: [line(.removed, 1, nil, "old")])).hunks[0].splitRows
        XCTAssertEqual(deletion[0].old?.kind, .removed)
        XCTAssertNil(deletion[0].new)
    }

    func testFullFileAddsMarkerForPureDeletion() {
        let document = ReviewDiffDocument(file: fixture(
            old: "one\nremoved\ntwo",
            new: "one\ntwo",
            oldStart: 1,
            newStart: 1,
            lines: [
                line(.context, 1, 1, "one"),
                line(.removed, 2, nil, "removed"),
                line(.context, 3, 2, "two")
            ]
        ))

        let markers = document.fullFileRows.compactMap { row -> FullFileDeletionMarker? in
            guard case .deletion(let marker) = row else { return nil }
            return marker
        }
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].removedLineCount, 1)
        XCTAssertEqual(markers[0].insertionLine, 2)
        XCTAssertEqual(markers[0].removedLines, ["removed"])
        XCTAssertEqual(document.fullFileTargetID(forHunkID: document.hunks[0].id), markers[0].id)
    }

    func testDeletedFileUsesOldSideAndHighlightsRemovedLines() {
        let file = fixture(old: "a\nb", new: "", status: .deleted, lines: [
            line(.removed, 1, nil, "a"), line(.removed, 2, nil, "b")
        ])
        let document = ReviewDiffDocument(file: file)
        XCTAssertEqual(document.displayedFullFileSide, .old)
        let sources = document.fullFileRows.compactMap { row -> FullFileSourceRow? in
            guard case .source(let source) = row else { return nil }
            return source
        }
        XCTAssertEqual(sources.map(\.kind), [.removed, .removed])
        XCTAssertEqual(sources.map(\.side), [.old, .old])
    }

    func testFullFileContextRowsRetainAnAnnotatableSideAndLineNumber() {
        let document = ReviewDiffDocument(file: fixture(
            old: "same\nchanged",
            new: "same\nnew",
            lines: [
                line(.context, 1, 1, "same"),
                line(.removed, 2, nil, "changed"),
                line(.added, nil, 2, "new")
            ]
        ))
        let context = document.fullFileRows.compactMap { row -> FullFileSourceRow? in
            guard case .source(let source) = row, source.kind == .context else { return nil }
            return source
        }.first

        XCTAssertEqual(context?.side, .new)
        XCTAssertEqual(context?.diffLine.newLineNumber, 1)
        XCTAssertEqual(context?.content, "same")
    }

    func testLineSelectionNormalizesReverseRangesAndExtendsFromAnchor() {
        let fileID = "repo:file.rs"
        let selection = ReviewLineSelection(
            fileID: fileID,
            side: .new,
            anchorLine: 10,
            focusLine: 6
        )

        XCTAssertEqual(selection.lines, 6...10)
        XCTAssertEqual(selection.lineCount, 5)
        XCTAssertTrue(selection.contains(fileID: fileID, side: .new, line: 8))
        XCTAssertFalse(selection.contains(fileID: fileID, side: .old, line: 8))
        XCTAssertFalse(selection.contains(fileID: "other", side: .new, line: 8))

        let extended = selection.extending(to: 14)
        XCTAssertEqual(extended.anchorLine, 10)
        XCTAssertEqual(extended.lines, 10...14)
        XCTAssertEqual(extended.lineCount, 5)
    }

    func testClickSelectionOnlyExtendsWithinTheSameFileAndDiffSide() {
        let initial = ReviewLineSelection(fileID: "repo:file.rs", side: .old, anchorLine: 8)

        let extended = ReviewLineSelection.selectionAfterClick(
            current: initial,
            fileID: "repo:file.rs",
            side: .old,
            line: 11,
            extending: true
        )
        XCTAssertEqual(extended.lines, 8...11)

        let ordinaryClick = ReviewLineSelection.selectionAfterClick(
            current: extended,
            fileID: "repo:file.rs",
            side: .old,
            line: 4,
            extending: false
        )
        XCTAssertEqual(ordinaryClick.lines, 4...4)

        let otherSide = ReviewLineSelection.selectionAfterClick(
            current: extended,
            fileID: "repo:file.rs",
            side: .new,
            line: 12,
            extending: true
        )
        XCTAssertEqual(otherSide.side, .new)
        XCTAssertEqual(otherSide.lines, 12...12)

        let otherFile = ReviewLineSelection.selectionAfterClick(
            current: extended,
            fileID: "repo:other.rs",
            side: .old,
            line: 3,
            extending: true
        )
        XCTAssertEqual(otherFile.fileID, "repo:other.rs")
        XCTAssertEqual(otherFile.lines, 3...3)
    }

    func testDocumentExtractsSelectedCodeAndNumberedSurroundingContext() {
        let document = ReviewDiffDocument(file: fixture(
            old: "old one\nold two\nold three\nold four\nold five",
            new: "new one\nnew two\nnew three\nnew four\nnew five",
            lines: [line(.context, 1, 1, "new one")]
        ))

        XCTAssertEqual(document.sourceExcerpt(side: .new, lines: 2...4), "new two\nnew three\nnew four")
        XCTAssertEqual(document.sourceExcerpt(side: .old, lines: 2...3), "old two\nold three")
        XCTAssertEqual(
            document.surroundingContext(side: .new, lines: 2...3, padding: 1),
            "1  new one\n2  new two\n3  new three\n4  new four"
        )
    }

    func testPresentationIdentityIsStableAcrossEquivalentDiffInstances() {
        let first = ReviewDiffDocument(file: fixture(lines: [line(.added, nil, 1, "x")]))
        let second = ReviewDiffDocument(file: fixture(lines: [line(.added, nil, 1, "x")]))
        XCTAssertEqual(first.hunks.map(\.id), second.hunks.map(\.id))
        XCTAssertEqual(first.hunks.flatMap(\.unifiedRows).map(\.id), second.hunks.flatMap(\.unifiedRows).map(\.id))
        XCTAssertEqual(first.hunks.flatMap(\.splitRows).map(\.id), second.hunks.flatMap(\.splitRows).map(\.id))
    }

    func testLargePresentationBuildIsLinearEnoughForInteractiveUse() {
        let lines = (1...50_000).map { (index: Int) -> DiffLine in
            line(.context, index, index, "let value\(index) = \(index)")
        }
        measure {
            let document = ReviewDiffDocument(file: fixture(old: "", new: "", oldStart: 1, newStart: 1, lines: lines))
            XCTAssertEqual(document.hunks[0].splitRows.count, 50_000)
        }
    }

    private func fixture(
        old: String = "",
        new: String = "",
        status: FileStatus = .modified,
        oldStart: Int = 1,
        newStart: Int = 1,
        lines: [DiffLine]
    ) -> WorkspaceFileDiff {
        let hunk = DiffHunk(
            oldStart: oldStart,
            oldCount: lines.filter { $0.kind != .added }.count,
            newStart: newStart,
            newCount: lines.filter { $0.kind != .removed }.count,
            lines: lines
        )
        return WorkspaceFileDiff(repositoryID: UUID(), repositoryName: "repo", diff: FileDiff(path: "file.rs", status: status, hunks: [hunk]), oldContent: old, newContent: new)
    }

    private func line(_ kind: DiffLineKind, _ old: Int?, _ new: Int?, _ content: String) -> DiffLine {
        DiffLine(kind: kind, oldLineNumber: old, newLineNumber: new, content: content)
    }
}
