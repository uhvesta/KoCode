import XCTest
@testable import AvestaCore

@MainActor
final class CodeReviewSessionTests: XCTestCase {
    func testMarkdownDumpIncludesFilesLinesSnippetsAndComments() {
        let file = FileDiff(
            path: "Sources/App.swift",
            status: .modified,
            hunks: []
        )
        let session = CodeReviewSession(
            diffSpec: "main...HEAD",
            repoPath: URL(fileURLWithPath: "/tmp/repo"),
            files: [file]
        )

        session.addComment(
            fileID: file.id,
            line: 12,
            highlightedText: "let value = 1",
            text: "Prefer a named constant here."
        )

        let markdown = session.toMarkdown()

        XCTAssertTrue(markdown.contains("# Code Review: main...HEAD @"))
        XCTAssertTrue(markdown.contains("## `Sources/App.swift`"))
        XCTAssertTrue(markdown.contains("### Line 12"))
        XCTAssertTrue(markdown.contains("```swift"))
        XCTAssertTrue(markdown.contains("Prefer a named constant here."))
    }
}
