import XCTest
@testable import AvestaTerminal

final class TerminalOutputSanitizerTests: XCTestCase {
    func testStripsCSIAndOSCSequencesForDisplay() {
        let raw = "\u{001B}[1m\u{001B}[7m%\u{001B}[27m\u{001B}[0m \u{001B}]2;title\u{0007}~/workspaces/Default \u{001B}[31m↵\u{001B}[0m"

        let display = TerminalOutputSanitizer.displayText(from: raw)

        XCTAssertEqual(display, "% ~/workspaces/Default ↵")
    }

    func testDropsNonPrintingControlsButKeepsTabsAndNewlines() {
        let raw = "one\u{0000}\ttwo\rthree\n"

        XCTAssertEqual(TerminalOutputSanitizer.displayText(from: raw), "one\ttwo\nthree\n")
    }

    func testScreenBufferHandlesCarriageReturnAndEraseLine() {
        var buffer = TerminalScreenBuffer()

        buffer.write("loading")
        buffer.write("\r\u{001B}[Kdone\n")

        XCTAssertEqual(buffer.renderedText, "done\n")
    }

    func testScreenBufferIgnoresPromptControlSequences() {
        var buffer = TerminalScreenBuffer()

        buffer.write("\u{001B}]2;title\u{0007}\u{001B}[1m~/workspaces/Default %# \u{001B}[0m")

        XCTAssertEqual(buffer.renderedText, "~/workspaces/Default %# ")
    }
}
