import XCTest
@testable import AvestaTerminal

final class TerminalOutputSanitizerTests: XCTestCase {
    func testSanitizerIsNotificationOnlyAndRemovesANSI() {
        XCTAssertEqual(TerminalOutputSanitizer.notificationText(from: "\u{001B}[31mfailed\u{001B}[0m"), "failed")
    }

    func testProductionTerminalCodeContainsNoForbiddenImplementation() throws {
        let root = try workspaceRoot()
        let terminalRoot = root.appending(path: "Sources/AvestaTerminal", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: terminalRoot, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let source = try files.map { try String(contentsOf: $0) }.joined(separator: "\n")
        for forbidden in ["forkpty", "openpty", "TerminalScreenBuffer", "Process()", "render_grid_json", "process_output("] {
            XCTAssertFalse(source.contains(forbidden), "production terminal source introduced forbidden API: \(forbidden)")
        }
        XCTAssertTrue(source.contains("ghostty_surface_new"))
        XCTAssertTrue(source.contains("ghostty_surface_text_input"))
    }

    func testPinnedHeaderAndCompiledLibraryRevisionMatch() throws {
        let pinned = try readWorkspaceFile("third_party/GHOSTTY_REVISION").trimmingCharacters(in: .whitespacesAndNewlines)
        if let built = try? readWorkspaceFile("GhosttyKit.xcframework/.ghostty_sha").trimmingCharacters(in: .whitespacesAndNewlines) {
            XCTAssertEqual(pinned, built)
        } else {
            XCTAssertTrue(try readWorkspaceFile("MODULE.bazel").contains("commit = \"\(pinned)\""))
        }
    }

    private func workspaceRoot() throws -> URL {
        if let root = workspaceCandidates().first(where: { FileManager.default.fileExists(atPath: $0.appending(path: "third_party/GHOSTTY_REVISION").path) }) { return root }
        throw CocoaError(.fileNoSuchFile)
    }

    private func readWorkspaceFile(_ relativePath: String) throws -> String {
        for root in workspaceCandidates() {
            if let value = try? String(contentsOf: root.appending(path: relativePath), encoding: .utf8) { return value }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func workspaceCandidates() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let path = environment["BUILD_WORKSPACE_DIRECTORY"] { candidates.append(URL(fileURLWithPath: path, isDirectory: true)) }
        if let path = environment["TEST_SRCDIR"] {
            let runfiles = URL(fileURLWithPath: path, isDirectory: true)
            candidates.append(runfiles.appending(path: "_main", directoryHint: .isDirectory))
            candidates.append(runfiles.appending(path: "avestacode", directoryHint: .isDirectory))
        }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        return candidates
    }
}
