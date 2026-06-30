import Foundation
import SwiftTreeSitter
import SwiftUI
import TreeSitterSwift

struct SyntaxHighlightedLine: Equatable {
    let lineNumber: Int
    let content: AttributedString
}

enum SwiftSyntaxHighlighter {
    static func highlightedLines(for source: String, path: String) -> [SyntaxHighlightedLine] {
        let plainLines = sourceLines(for: source)
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "swift" else {
            return plainLines
        }

        do {
            let languageConfig = try swiftLanguageConfiguration()
            let parser = Parser()
            try parser.setLanguage(languageConfig.language)
            guard let tree = parser.parse(source),
                  let query = languageConfig.queries[.highlights] else {
                return plainLines
            }

            let highlights = query
                .execute(in: tree)
                .resolve(with: .init(string: source))
                .highlights()

            return apply(highlights: highlights, to: source)
        } catch {
            return plainLines
        }
    }

    private static func swiftLanguageConfiguration() throws -> LanguageConfiguration {
        let language = Language(tree_sitter_swift())
        if let queriesURL = swiftQueriesDirectoryURL() {
            return try LanguageConfiguration(language, name: "Swift", queriesURL: queriesURL)
        }
        return try LanguageConfiguration(language, name: "Swift")
    }

    private static func swiftQueriesDirectoryURL() -> URL? {
        let fileManager = FileManager.default
        let bundleName = "TreeSitterSwift_TreeSitterSwift.bundle"
        let roots = candidateResourceRoots()

        for root in roots {
            let candidates = [
                root.appendingPathComponent(bundleName, isDirectory: true)
                    .appendingPathComponent("queries", isDirectory: true),
                root.appendingPathComponent(bundleName, isDirectory: true)
                    .appendingPathComponent("Contents/Resources/queries", isDirectory: true),
                root.appendingPathComponent("queries", isDirectory: true)
            ]

            for candidate in candidates where fileManager.isReadableFile(atPath: candidate.appendingPathComponent("highlights.scm").path) {
                return candidate
            }
        }

        return nil
    }

    private static func candidateResourceRoots() -> [URL] {
        var roots: [URL] = []

        func append(_ url: URL?) {
            guard let url else { return }
            let standardized = url.standardizedFileURL
            guard !roots.contains(standardized) else { return }
            roots.append(standardized)
        }

        append(Bundle.main.resourceURL)
        append(Bundle.main.bundleURL)

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            append(bundle.resourceURL)
            append(bundle.bundleURL)
            append(bundle.bundleURL.deletingLastPathComponent())
        }

        if let executableURL = Bundle.main.executableURL {
            append(executableURL.deletingLastPathComponent())
            append(executableURL.deletingLastPathComponent().deletingLastPathComponent())
            append(executableURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        append(workingDirectory.appendingPathComponent(".build/debug", isDirectory: true))
        append(workingDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true))
        append(workingDirectory.appendingPathComponent(".build/release", isDirectory: true))
        append(workingDirectory.appendingPathComponent(".build/arm64-apple-macosx/release", isDirectory: true))

        return roots
    }

    private static func sourceLines(for source: String) -> [SyntaxHighlightedLine] {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, content in
                SyntaxHighlightedLine(lineNumber: index + 1, content: AttributedString(String(content)))
            }
    }

    private static func apply(highlights: [NamedRange], to source: String) -> [SyntaxHighlightedLine] {
        let lineRanges = lineRanges(in: source)
        let nsSource = source as NSString

        return lineRanges.enumerated().map { index, lineRange in
            let rawLine = nsSource.substring(with: lineRange.contentRange)
            var attributed = AttributedString(rawLine)

            for highlight in highlights {
                let overlap = NSIntersectionRange(highlight.range, lineRange.contentRange)
                guard overlap.length > 0 else { continue }

                let localRange = NSRange(location: overlap.location - lineRange.contentRange.location, length: overlap.length)
                guard let range = Range(localRange, in: rawLine),
                      let attributedRange = Range(range, in: attributed),
                      let style = style(for: highlight.name) else {
                    continue
                }

                attributed[attributedRange].foregroundColor = style.foregroundColor
                if style.isItalic {
                    attributed[attributedRange].inlinePresentationIntent = .emphasized
                }
            }

            return SyntaxHighlightedLine(lineNumber: index + 1, content: attributed)
        }
    }

    private static func lineRanges(in source: String) -> [LineRange] {
        let nsSource = source as NSString
        var ranges: [LineRange] = []
        var location = 0

        while location <= nsSource.length {
            let searchRange = NSRange(location: location, length: nsSource.length - location)
            let nextNewline = nsSource.range(of: "\n", options: [], range: searchRange)
            let lineEnd = nextNewline.location == NSNotFound ? nsSource.length : nextNewline.location
            ranges.append(LineRange(contentRange: NSRange(location: location, length: lineEnd - location)))

            guard nextNewline.location != NSNotFound else { break }
            location = nextNewline.location + nextNewline.length
        }

        return ranges
    }

    private static func style(for captureName: String) -> HighlightStyle? {
        if captureName.contains("comment") {
            return HighlightStyle(foregroundColor: .secondary, isItalic: true)
        }
        if captureName.contains("string") {
            return HighlightStyle(foregroundColor: Color(red: 0.70, green: 0.86, blue: 0.55))
        }
        if captureName.contains("number") || captureName.contains("constant") {
            return HighlightStyle(foregroundColor: Color(red: 0.98, green: 0.67, blue: 0.38))
        }
        if captureName.contains("keyword") || captureName.contains("operator") {
            return HighlightStyle(foregroundColor: Color(red: 0.86, green: 0.66, blue: 0.98))
        }
        if captureName.contains("type") || captureName.contains("constructor") {
            return HighlightStyle(foregroundColor: Color(red: 0.48, green: 0.78, blue: 1.00))
        }
        if captureName.contains("function") || captureName.contains("method") {
            return HighlightStyle(foregroundColor: Color(red: 1.00, green: 0.82, blue: 0.48))
        }
        if captureName.contains("property") || captureName.contains("variable.parameter") {
            return HighlightStyle(foregroundColor: Color(red: 0.66, green: 0.86, blue: 1.00))
        }

        return nil
    }
}

private struct LineRange {
    let contentRange: NSRange
}

private struct HighlightStyle {
    let foregroundColor: Color
    var isItalic = false
}
