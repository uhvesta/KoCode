import XCTest
@testable import AvestaCore

final class WorkspaceTabNavigationTests: XCTestCase {
    func testAdjacentNavigationWrapsInPersistedOrder() {
        let tabs = makeTabs(count: 3)
        var workspace = makeWorkspace(tabs: tabs)
        workspace.layout.primaryTabID = tabs[0].id

        XCTAssertEqual(workspace.adjacentTabID(offset: 1), tabs[1].id)
        XCTAssertEqual(workspace.adjacentTabID(offset: -1), tabs[2].id)

        workspace.layout.primaryTabID = tabs[2].id
        XCTAssertEqual(workspace.adjacentTabID(offset: 1), tabs[0].id)
        XCTAssertEqual(workspace.adjacentTabID(offset: -1), tabs[1].id)
    }

    func testNumberShortcutsSelectPositionsAndNineSelectsLast() {
        let tabs = makeTabs(count: 5)
        let workspace = makeWorkspace(tabs: tabs)

        XCTAssertEqual(workspace.tabID(shortcutNumber: 1), tabs[0].id)
        XCTAssertEqual(workspace.tabID(shortcutNumber: 5), tabs[4].id)
        XCTAssertEqual(workspace.tabID(shortcutNumber: 9), tabs[4].id)
        XCTAssertNil(workspace.tabID(shortcutNumber: 6))
        XCTAssertNil(workspace.tabID(shortcutNumber: 0))
    }

    private func makeTabs(count: Int) -> [TabRecord] {
        let workspaceID = UUID()
        return (0..<count).map {
            TabRecord(workspaceID: workspaceID, kind: .terminal, title: "Terminal \($0 + 1)", sortIndex: $0)
        }
    }

    private func makeWorkspace(tabs: [TabRecord]) -> WorkspaceRecord {
        WorkspaceRecord(
            id: tabs.first?.workspaceID ?? UUID(),
            name: "Workspace",
            path: URL(fileURLWithPath: "/tmp/workspace"),
            tabs: tabs
        )
    }
}
