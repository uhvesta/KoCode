import XCTest
@testable import AvestaCore

final class GitDiffParserTests: XCTestCase {
    func testParsesModifiedFileWithLineNumbers() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,3 +1,4 @@
         import SwiftUI
        -let title = "Old"
        +let title = "New"
        +let subtitle = "Workbench"
         print(title)
        """

        let files = try GitDiffParser().parse(diff)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "Sources/App.swift")
        XCTAssertEqual(files[0].status, .modified)
        XCTAssertEqual(files[0].hunks.count, 1)
        XCTAssertEqual(files[0].hunks[0].lines.map(\.kind), [.context, .removed, .added, .added, .context])
        XCTAssertEqual(files[0].hunks[0].lines[1].oldLineNumber, 2)
        XCTAssertNil(files[0].hunks[0].lines[1].newLineNumber)
        XCTAssertEqual(files[0].hunks[0].lines[2].newLineNumber, 2)
    }

    func testParsesAddedFile() throws {
        let diff = """
        diff --git a/README.md b/README.md
        new file mode 100644
        index 0000000..1111111
        --- /dev/null
        +++ b/README.md
        @@ -0,0 +1,2 @@
        +# AvestaCode
        +Agentic workbench
        """

        let file = try XCTUnwrap(GitDiffParser().parse(diff).first)

        XCTAssertEqual(file.path, "README.md")
        XCTAssertEqual(file.status, .added)
        XCTAssertEqual(file.hunks[0].newStart, 1)
        XCTAssertEqual(file.hunks[0].lines.map(\.newLineNumber), [1, 2])
    }

    func testParsesRename() throws {
        let diff = """
        diff --git a/Old.swift b/New.swift
        similarity index 93%
        rename from Old.swift
        rename to New.swift
        --- a/Old.swift
        +++ b/New.swift
        @@ -1 +1 @@
        -old
        +new
        """

        let file = try XCTUnwrap(GitDiffParser().parse(diff).first)

        XCTAssertEqual(file.oldPath, "Old.swift")
        XCTAssertEqual(file.path, "New.swift")
        XCTAssertEqual(file.status, .renamed)
    }
}
