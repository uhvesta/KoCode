import XCTest
import SwiftUI
@testable import AvestaCore
@testable import AvestaUI

@MainActor
final class AvestaUITests: XCTestCase {
    func testMainWindowCanBeConstructedWithInjectedTerminalOutputHandler() {
        let state = AppState()
        state.createWorkspace(name: "UITest")

        let view = MainWindow { _, _ in }
            .environment(state)

        XCTAssertNotNil(view)
    }
}
