import Foundation
import SwiftTreeSitter
import SwiftUI
import TreeSitterSwift

struct SyntaxHighlightedLine: Equatable, Sendable {
    let lineNumber: Int
    let content: AttributedString
}

enum ReviewSyntaxLanguage: String, CaseIterable, Sendable {
    case swift, rust, starlark, toml, json, yaml, markdown, shell, python, javascript, typescript, protobuf

    static func resolve(path: String) -> ReviewSyntaxLanguage? {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if name == "build" || name == "build.bazel" || name == "module.bazel" || ext == "bzl" { return .starlark }
        if name == "cargo.lock" || ext == "toml" { return .toml }
        switch ext {
        case "swift": return .swift
        case "rs": return .rust
        case "json", "jsonc": return .json
        case "yaml", "yml": return .yaml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .shell
        case "py", "pyi": return .python
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx", "mts", "cts": return .typescript
        case "proto": return .protobuf
        default: return nil
        }
    }
}

/// Whole-file syntax highlighting with a bounded process-local cache. Swift is
/// parsed with the pinned tree-sitter grammar. Other common review languages
/// use a conservative lexical highlighter until pinned grammar products are
/// available in both SwiftPM and Bazel; unknown inputs stay plain text.
enum SyntaxHighlighter {
    // Whole-file highlighting creates an attributed value for every visible
    // line. Above these bounds the plain monospaced representation is much
    // smoother to scroll and avoids a large main-thread dictionary swap.
    static let automaticByteLimit = 512 * 1_024
    static let automaticLineLimit = 10_000

    static func highlightedLines(for source: String, path: String) -> [SyntaxHighlightedLine] {
        let language = ReviewSyntaxLanguage.resolve(path: path)
        let key = CacheKey(path: path, source: source, language: language)
        if let cached = cache.value(for: key) { return cached }

        let plain = sourceLines(for: source)
        guard source.utf8.count <= automaticByteLimit,
              plain.count <= automaticLineLimit,
              let language else {
            cache.insert(plain, for: key)
            return plain
        }

        let highlighted: [SyntaxHighlightedLine]
        if language == .swift {
            highlighted = swiftHighlightedLines(source: source) ?? lexicalHighlightedLines(source: source, language: language)
        } else {
            highlighted = lexicalHighlightedLines(source: source, language: language)
        }
        cache.insert(highlighted, for: key)
        return highlighted
    }

    /// The Review viewport uses nil to keep its normal plain-text row fallback
    /// instead of materializing tens of thousands of plain AttributedStrings.
    /// The work is intended to run off the main actor.
    static func automaticHighlightedLines(for source: String, path: String) -> [SyntaxHighlightedLine]? {
        guard source.utf8.count <= automaticByteLimit,
              source.reduce(into: 1, { if $1 == "\n" { $0 += 1 } }) <= automaticLineLimit,
              ReviewSyntaxLanguage.resolve(path: path) != nil else {
            return nil
        }
        return highlightedLines(for: source, path: path)
    }

    static func plainLines(for source: String) -> [SyntaxHighlightedLine] { sourceLines(for: source) }

    private static let cache = HighlightCache(maximumCost: 24 * 1_024 * 1_024)

    private static func swiftHighlightedLines(source: String) -> [SyntaxHighlightedLine]? {
        do {
            let languageConfig = try swiftLanguageConfiguration()
            let parser = Parser()
            try parser.setLanguage(languageConfig.language)
            guard let tree = parser.parse(source), let query = languageConfig.queries[.highlights] else { return nil }
            let highlights = query.execute(in: tree).resolve(with: .init(string: source)).highlights()
            return apply(highlights: highlights, to: source)
        } catch {
            return nil
        }
    }

    private static func lexicalHighlightedLines(source: String, language: ReviewSyntaxLanguage) -> [SyntaxHighlightedLine] {
        sourceLines(for: source).map { line in
            var value = line.content
            let raw = String(value.characters)
            for token in lexicalTokens(in: raw, language: language) {
                guard let stringRange = Range(token.range, in: raw),
                      let attributedRange = Range(stringRange, in: value) else { continue }
                value[attributedRange].foregroundColor = token.color
                if token.italic { value[attributedRange].inlinePresentationIntent = .emphasized }
            }
            return SyntaxHighlightedLine(lineNumber: line.lineNumber, content: value)
        }
    }

    private static func lexicalTokens(in line: String, language: ReviewSyntaxLanguage) -> [LexicalToken] {
        var patterns: [(String, Color, Bool)] = []
        switch language {
        case .markdown:
            patterns = [
                (#"^\s{0,3}#{1,6}\s.*$"#, .reviewKeyword, false),
                (#"`[^`]+`"#, .reviewString, false),
                (#"\*\*[^*]+\*\*|__[^_]+__"#, .reviewFunction, false),
                (#"\[[^\]]+\]\([^\)]+\)"#, .reviewType, false)
            ]
        case .toml:
            patterns = [
                (#"^\s*\[\[?[^\]]+\]\]?"#, .reviewType, false),
                (#"^\s*[A-Za-z0-9_.-]+(?=\s*=)"#, .reviewProperty, false),
                (#"\"(?:\\.|[^\"])*\"|'[^']*'"#, .reviewString, false),
                (#"\b(?:true|false)\b|\b\d+(?:\.\d+)?\b"#, .reviewNumber, false),
                (#"#.*$"#, .secondary, true)
            ]
        case .json:
            patterns = [
                (#"\"(?:\\.|[^\"])*\"(?=\s*:)"#, .reviewProperty, false),
                (#"\"(?:\\.|[^\"])*\""#, .reviewString, false),
                (#"\b(?:true|false|null)\b"#, .reviewKeyword, false),
                (#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .reviewNumber, false)
            ]
        case .yaml:
            patterns = [
                (#"^\s*[-]?[ ]*[A-Za-z0-9_.-]+(?=\s*:)"#, .reviewProperty, false),
                (#"\"(?:\\.|[^\"])*\"|'[^']*'"#, .reviewString, false),
                (#"\b(?:true|false|null|yes|no)\b|\b\d+(?:\.\d+)?\b"#, .reviewNumber, false),
                (#"#.*$"#, .secondary, true)
            ]
        case .rust:
            patterns = codePatterns(
                keywords: "as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while",
                comment: #"//.*$"#
            )
        case .python, .starlark:
            patterns = codePatterns(
                keywords: "and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|load|None|not|or|pass|raise|return|True|try|while|with|yield",
                comment: #"#.*$"#
            )
        case .shell:
            patterns = codePatterns(
                keywords: "case|do|done|elif|else|esac|export|fi|for|function|if|in|local|readonly|select|then|until|while",
                comment: #"#.*$"#
            )
        case .javascript, .typescript:
            patterns = codePatterns(
                keywords: "async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|enum|export|extends|false|finally|for|from|function|if|implements|import|in|instanceof|interface|let|new|null|of|package|private|protected|public|return|static|super|switch|this|throw|true|try|type|typeof|undefined|var|void|while|with|yield",
                comment: #"//.*$"#
            )
        case .protobuf:
            patterns = codePatterns(
                keywords: "edition|enum|extend|extensions|import|map|message|oneof|option|optional|package|public|repeated|required|reserved|returns|rpc|service|stream|syntax|to",
                comment: #"//.*$"#
            )
        case .swift:
            patterns = codePatterns(
                keywords: "actor|as|associatedtype|async|await|break|case|catch|class|continue|default|defer|deinit|do|else|enum|extension|fallthrough|false|fileprivate|for|func|guard|if|import|in|init|inout|internal|is|let|nil|nonisolated|open|operator|private|protocol|public|repeat|required|rethrows|return|self|Self|some|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while",
                comment: #"//.*$"#
            )
        }

        var tokens: [LexicalToken] = []
        for (pattern, color, italic) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            tokens.append(contentsOf: regex.matches(in: line, range: range).map { LexicalToken(range: $0.range, color: color, italic: italic) })
        }
        return tokens
    }

    private static func codePatterns(keywords: String, comment: String) -> [(String, Color, Bool)] {
        [
            (#"\b(?:"# + keywords + #")\b"#, .reviewKeyword, false),
            (#"\"(?:\\.|[^\"])*\"|'(?:\\.|[^'])*'"#, .reviewString, false),
            (#"\b\d+(?:\.\d+)?\b"#, .reviewNumber, false),
            (#"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#, .reviewFunction, false),
            (comment, .secondary, true)
        ]
    }

    private static func swiftLanguageConfiguration() throws -> LanguageConfiguration {
        let language = Language(tree_sitter_swift())
        if let queriesURL = swiftQueriesDirectoryURL() { return try LanguageConfiguration(language, name: "Swift", queriesURL: queriesURL) }
        return try LanguageConfiguration(language, name: "Swift")
    }

    private static func swiftQueriesDirectoryURL() -> URL? {
        let fileManager = FileManager.default
        let bundleName = "TreeSitterSwift_TreeSitterSwift.bundle"
        for root in candidateResourceRoots() {
            let candidates = [
                root.appendingPathComponent(bundleName, isDirectory: true).appendingPathComponent("queries", isDirectory: true),
                root.appendingPathComponent(bundleName, isDirectory: true).appendingPathComponent("Contents/Resources/queries", isDirectory: true),
                root.appendingPathComponent("queries", isDirectory: true)
            ]
            for candidate in candidates where fileManager.isReadableFile(atPath: candidate.appendingPathComponent("highlights.scm").path) { return candidate }
        }
        return nil
    }

    private static func candidateResourceRoots() -> [URL] {
        var roots: [URL] = []
        func append(_ url: URL?) {
            guard let standardized = url?.standardizedFileURL, !roots.contains(standardized) else { return }
            roots.append(standardized)
        }
        append(Bundle.main.resourceURL)
        append(Bundle.main.bundleURL)
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            append(bundle.resourceURL); append(bundle.bundleURL); append(bundle.bundleURL.deletingLastPathComponent())
        }
        for key in ["RUNFILES_DIR", "TEST_SRCDIR"] {
            if let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty { appendBazelRunfilesRoot(URL(fileURLWithPath: raw, isDirectory: true), to: &roots) }
        }
        if let executableURL = Bundle.main.executableURL {
            append(executableURL.deletingLastPathComponent())
            append(executableURL.deletingLastPathComponent().deletingLastPathComponent())
            append(executableURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            appendBazelRunfilesRoot(executableURL.deletingLastPathComponent().appendingPathComponent(executableURL.lastPathComponent + ".runfiles", isDirectory: true), to: &roots)
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        append(cwd.appendingPathComponent(".build/debug", isDirectory: true))
        append(cwd.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true))
        append(cwd.appendingPathComponent(".build/release", isDirectory: true))
        return roots
    }

    private static func appendBazelRunfilesRoot(_ root: URL, to roots: inout [URL]) {
        for url in [root, root.appendingPathComponent("rules_swift_package_manager++swift_deps+swiftpkg_tree_sitter_swift", isDirectory: true), root.appendingPathComponent("tree_sitter_swift", isDirectory: true)] {
            let value = url.standardizedFileURL
            if !roots.contains(value) { roots.append(value) }
        }
    }

    private static func sourceLines(for source: String) -> [SyntaxHighlightedLine] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
            SyntaxHighlightedLine(lineNumber: $0.offset + 1, content: AttributedString(String($0.element)))
        }
    }

    private static func apply(highlights: [NamedRange], to source: String) -> [SyntaxHighlightedLine] {
        let ranges = lineRanges(in: source)
        let nsSource = source as NSString
        return ranges.enumerated().map { index, lineRange in
            let rawLine = nsSource.substring(with: lineRange)
            var attributed = AttributedString(rawLine)
            for highlight in highlights {
                let overlap = NSIntersectionRange(highlight.range, lineRange)
                guard overlap.length > 0 else { continue }
                let local = NSRange(location: overlap.location - lineRange.location, length: overlap.length)
                guard let stringRange = Range(local, in: rawLine), let range = Range(stringRange, in: attributed), let style = style(for: highlight.name) else { continue }
                attributed[range].foregroundColor = style.0
                if style.1 { attributed[range].inlinePresentationIntent = .emphasized }
            }
            return SyntaxHighlightedLine(lineNumber: index + 1, content: attributed)
        }
    }

    private static func lineRanges(in source: String) -> [NSRange] {
        let ns = source as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location <= ns.length {
            let newline = ns.range(of: "\n", range: NSRange(location: location, length: ns.length - location))
            let end = newline.location == NSNotFound ? ns.length : newline.location
            ranges.append(NSRange(location: location, length: end - location))
            guard newline.location != NSNotFound else { break }
            location = newline.location + newline.length
        }
        return ranges
    }

    private static func style(for capture: String) -> (Color, Bool)? {
        if capture.contains("comment") { return (.secondary, true) }
        if capture.contains("string") { return (.reviewString, false) }
        if capture.contains("number") || capture.contains("constant") { return (.reviewNumber, false) }
        if capture.contains("keyword") || capture.contains("operator") { return (.reviewKeyword, false) }
        if capture.contains("type") || capture.contains("constructor") { return (.reviewType, false) }
        if capture.contains("function") || capture.contains("method") { return (.reviewFunction, false) }
        if capture.contains("property") || capture.contains("variable.parameter") { return (.reviewProperty, false) }
        return nil
    }
}

/// Compatibility shim for call sites and downstream users of the prototype.
enum SwiftSyntaxHighlighter {
    static func highlightedLines(for source: String, path: String) -> [SyntaxHighlightedLine] {
        SyntaxHighlighter.highlightedLines(for: source, path: path)
    }
}

private struct CacheKey: Hashable {
    let path: String
    let source: String
    let language: ReviewSyntaxLanguage?
}

private final class HighlightCache: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumCost: Int
    private var values: [CacheKey: ([SyntaxHighlightedLine], Int, UInt64)] = [:]
    private var counter: UInt64 = 0
    private var cost = 0

    init(maximumCost: Int) { self.maximumCost = maximumCost }

    func value(for key: CacheKey) -> [SyntaxHighlightedLine]? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = values[key] else { return nil }
        counter &+= 1
        values[key] = (entry.0, entry.1, counter)
        return entry.0
    }

    func insert(_ lines: [SyntaxHighlightedLine], for key: CacheKey) {
        lock.lock(); defer { lock.unlock() }
        counter &+= 1
        let newCost = key.source.utf8.count * 2
        if let old = values[key] { cost -= old.1 }
        values[key] = (lines, newCost, counter)
        cost += newCost
        while cost > maximumCost, let victim = values.min(by: { $0.value.2 < $1.value.2 }) {
            cost -= victim.value.1
            values.removeValue(forKey: victim.key)
        }
    }
}

private struct LexicalToken {
    let range: NSRange
    let color: Color
    let italic: Bool
}

private extension Color {
    static let reviewString = Color(red: 0.70, green: 0.86, blue: 0.55)
    static let reviewNumber = Color(red: 0.98, green: 0.67, blue: 0.38)
    static let reviewKeyword = Color(red: 0.86, green: 0.66, blue: 0.98)
    static let reviewType = Color(red: 0.48, green: 0.78, blue: 1.00)
    static let reviewFunction = Color(red: 1.00, green: 0.82, blue: 0.48)
    static let reviewProperty = Color(red: 0.66, green: 0.86, blue: 1.00)
}
