import AvestaCore
import SwiftUI

struct DiffLineView: View {
    let line: DiffLine
    let side: DiffSide
    var filePath: String?

    var body: some View {
        HStack(spacing: 0) {
            Text(lineNumber)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 8)

            Text(displayContent)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.trailing, 12)
        .background(background)
    }

    private var displayContent: AttributedString {
        guard let filePath else {
            return AttributedString(line.content.isEmpty ? " " : line.content)
        }

        let highlighted = SwiftSyntaxHighlighter
            .highlightedLines(for: line.content, path: filePath)
            .first?
            .content
        return line.content.isEmpty ? AttributedString(" ") : highlighted ?? AttributedString(line.content)
    }

    private var lineNumber: String {
        switch side {
        case .old:
            return line.oldLineNumber.map(String.init) ?? ""
        case .new:
            return line.newLineNumber.map(String.init) ?? ""
        }
    }

    private var background: Color {
        switch line.kind {
        case .added:
            return side == .new ? Color.green.opacity(0.14) : .clear
        case .removed:
            return side == .old ? Color.red.opacity(0.14) : .clear
        case .context:
            return .clear
        }
    }
}

enum DiffSide {
    case old
    case new
}
