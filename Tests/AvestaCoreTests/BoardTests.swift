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

    func testCreateWorkspaceCreatesBackingDirectory() {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AvestaCodeWorkspaceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let state = AppState(config: AppConfig(
            workspacesRoot: root.appending(path: "workspaces", directoryHint: .isDirectory),
            cacheRoot: root.appending(path: "cache", directoryHint: .isDirectory),
            notificationPatterns: []
        ))

        state.createWorkspace(name: "Default")

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "workspaces/Default").path))
        XCTAssertNil(state.lastErrorMessage)
    }
}
