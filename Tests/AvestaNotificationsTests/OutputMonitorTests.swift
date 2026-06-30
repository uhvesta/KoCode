import XCTest
@testable import AvestaNotifications

final class OutputMonitorTests: XCTestCase {
    func testBuffersLinesAndMatchesPatterns() {
        let monitor = OutputMonitor(patterns: [#"(?i)error"#, #"done\b"#])

        XCTAssertEqual(monitor.ingest("half"), [])
        XCTAssertEqual(monitor.ingest(" error\n").map(\.line), ["half error"])
        XCTAssertEqual(monitor.ingest("all done\n").map(\.pattern), [#"done\b"#])
    }
}
