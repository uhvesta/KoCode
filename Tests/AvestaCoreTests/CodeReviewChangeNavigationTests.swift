import XCTest
@testable import AvestaCore

final class CodeReviewChangeNavigationTests: XCTestCase {
    func testBuildsContiguousChangeRangesFromDiffLines() {
        let file = FileDiff(
            path: "Sources/App.swift",
            status: .modified,
            hunks: [
                DiffHunk(
                    oldStart: 1,
                    oldCount: 6,
                    newStart: 1,
                    newCount: 7,
                    lines: [
                        DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "import SwiftUI"),
                        DiffLine(kind: .removed, oldLineNumber: 2, newLineNumber: nil, content: "let oldTitle = true"),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 2, content: "let newTitle = true"),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 3, content: "let subtitle = true"),
                        DiffLine(kind: .context, oldLineNumber: 3, newLineNumber: 4, content: "struct App {}"),
                        DiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 7, content: "extension App {}")
                    ]
                )
            ]
        )

        XCTAssertEqual(
            CodeReviewChangeNavigation.changes(in: file),
            [
                CodeReviewChangeRange(startLine: 2, endLine: 3),
                CodeReviewChangeRange(startLine: 7, endLine: 7)
            ]
        )
    }

    func testReducerClampsPreviousNextAndExplicitFocus() {
        var state = CodeReviewNavigationState(
            changes: [
                CodeReviewChangeRange(startLine: 2, endLine: 3),
                CodeReviewChangeRange(startLine: 7, endLine: 7)
            ]
        )

        XCTAssertEqual(state.statusText, "Change 1 of 2")

        CodeReviewChangeNavigation.reduce(state: &state, action: .previousChange)
        XCTAssertEqual(state.focusedChangeIndex, 0)

        CodeReviewChangeNavigation.reduce(state: &state, action: .nextChange)
        XCTAssertEqual(state.focusedChangeIndex, 1)
        XCTAssertEqual(state.focusedChange, CodeReviewChangeRange(startLine: 7, endLine: 7))

        CodeReviewChangeNavigation.reduce(state: &state, action: .nextChange)
        XCTAssertEqual(state.focusedChangeIndex, 1)

        CodeReviewChangeNavigation.reduce(state: &state, action: .focusChange(-10))
        XCTAssertEqual(state.focusedChangeIndex, 0)

        CodeReviewChangeNavigation.reduce(state: &state, action: .focusChange(10))
        XCTAssertEqual(state.focusedChangeIndex, 1)
    }
}
