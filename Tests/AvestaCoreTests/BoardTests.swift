import XCTest
@testable import AvestaCore

@MainActor
final class BoardTests: XCTestCase {
    func testSendPrependsNonEmptyItems() {
        let board = BoardStore()

        board.send("first", source: "A")
        board.send("second", source: "B")
        board.send("   ", source: "ignored")

        XCTAssertEqual(board.items.map(\.content), ["second", "first"])
        XCTAssertEqual(board.paste()?.source, "B")
    }
}
