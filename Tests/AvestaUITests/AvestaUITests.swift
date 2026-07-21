import SwiftUI
import XCTest
@testable import AvestaCore
@testable import AvestaUI

@MainActor
final class AvestaUITests: XCTestCase {
    func testMainWindowCanBeConstructedWithSQLiteBackedModel() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AvestaUI-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteStateRepository(databaseURL: root.appending(path: "state.sqlite3"))
        let model = try ApplicationModel(repository: repository)
        XCTAssertNotNil(MainWindow(model: model))
    }

    func testSwiftSyntaxHighlighterAppliesForegroundAttributes() {
        let lines = SwiftSyntaxHighlighter.highlightedLines(for: "import SwiftUI\nstruct View {}", path: "View.swift")
        XCTAssertTrue(lines.flatMap(\.content.runs).contains { $0.foregroundColor != nil })
    }

    func testSyntaxLanguageRegistryCoversReviewLanguagesAndExactBazelNames() {
        let expectations: [(String, ReviewSyntaxLanguage)] = [
            ("File.swift", .swift), ("main.rs", .rust), ("Cargo.lock", .toml),
            ("BUILD", .starlark), ("MODULE.bazel", .starlark), ("defs.bzl", .starlark),
            ("config.json", .json), ("config.yaml", .yaml), ("README.md", .markdown),
            ("script.sh", .shell), ("tool.py", .python), ("index.tsx", .typescript),
            ("message.proto", .protobuf)
        ]
        for (path, language) in expectations { XCTAssertEqual(ReviewSyntaxLanguage.resolve(path: path), language, path) }
        XCTAssertNil(ReviewSyntaxLanguage.resolve(path: "image.png"))
    }

    func testSyntaxHighlightingAppliesToEveryRegisteredLanguageAndFallsBackPlain() {
        let fixtures: [(String, String)] = [
            ("main.rs", "fn main() { let value = 42; }"),
            ("Cargo.lock", "[[package]]\nname = \"demo\""),
            ("BUILD.bazel", "load(\"@rules//:defs.bzl\", \"target\")"),
            ("value.json", "{\"enabled\": true}"),
            ("value.yaml", "enabled: true"),
            ("README.md", "# Heading\n`code`"),
            ("script.sh", "if true; then echo \"yes\"; fi"),
            ("tool.py", "def run(): return True"),
            ("index.ts", "const value: number = 42"),
            ("message.proto", "message Result { optional string name = 1; }")
        ]
        for (path, source) in fixtures {
            let lines = SyntaxHighlighter.highlightedLines(for: source, path: path)
            XCTAssertTrue(lines.flatMap(\.content.runs).contains { $0.foregroundColor != nil }, path)
        }

        let plain = SyntaxHighlighter.highlightedLines(for: "opaque data", path: "file.unknown")
        XCTAssertFalse(plain.flatMap(\.content.runs).contains { $0.foregroundColor != nil })
    }

    func testWholeFileHighlightingPreservesLineNumbersAndMultilineContext() {
        let lines = SyntaxHighlighter.highlightedLines(for: "[[package]]\nname = \"demo\"\nversion = \"1.0\"", path: "Cargo.lock")
        XCTAssertEqual(lines.map(\.lineNumber), [1, 2, 3])
        XCTAssertEqual(lines.map { String($0.content.characters) }, ["[[package]]", "name = \"demo\"", "version = \"1.0\""])
    }
}
