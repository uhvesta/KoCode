import XCTest
import SwiftUI
import ComposableArchitecture
@testable import AvestaCore
@testable import AvestaUI

@MainActor
final class AvestaUITests: XCTestCase {
    func testMainWindowCanBeConstructedWithInjectedTerminalOutputHandler() {
        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let store = Store(initialState: AppFeature.State(
            workspaces: [
                AppFeature.WorkspaceState(
                    id: workspaceID,
                    name: "UITest",
                    path: URL(fileURLWithPath: "/tmp/UITest")
                )
            ],
            activeWorkspaceID: workspaceID
        )) {
            AppFeature()
        }

        let view = MainWindow(store: store) { _, _ in }

        XCTAssertNotNil(view)
    }

    func testSwiftSyntaxHighlighterAppliesForegroundAttributes() {
        let lines = SwiftSyntaxHighlighter.highlightedLines(
            for: """
            import SwiftUI

            struct AppView: View {
                var body: some View {
                    Text("Hello")
                }
            }
            """,
            path: "Sources/AppView.swift"
        )

        XCTAssertTrue(
            lines.flatMap(\.content.runs).contains { run in
                run.foregroundColor != nil
            }
        )
    }
}
