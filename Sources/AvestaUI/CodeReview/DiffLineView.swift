import AvestaCore
import SwiftUI

struct DiffLineView: View {
    let line: DiffLine
    let side: DiffSide
    var filePath: String?
    var isFocused = false
    var isLastTurnChange = false
    var showsAddComment = false
    var addComment: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Text(lineNumber)
                .font(.custom("Menlo", size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 10)

            Text(displayContent)
                .font(.custom("Menlo", size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsAddComment {
                Button(action: addComment) {
                    Image(systemName: "plus.bubble")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Add comment")
                .accessibilityLabel("Add Comment")
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 12)
        .background(background)
        .overlay(alignment: .leading) {
            if isFocused || isLastTurnChange {
                Rectangle()
                    .fill(isFocused ? Color.accentColor : Color.orange.opacity(0.85))
                    .frame(width: 3)
            }
        }
    }

    private var displayContent: AttributedString {
        guard !line.content.isEmpty else { return AttributedString(" ") }
        guard let filePath else { return AttributedString(line.content) }
        return SwiftSyntaxHighlighter
            .highlightedLines(for: line.content, path: filePath)
            .first?
            .content ?? AttributedString(line.content)
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
        if isLastTurnChange {
            return Color(red: 0.16, green: 0.11, blue: 0.04)
        }
        switch line.kind {
        case .added:
            return side == .new ? Color(red: 0.04, green: 0.12, blue: 0.07) : .clear
        case .removed:
            return side == .old ? Color(red: 0.15, green: 0.06, blue: 0.06) : .clear
        case .context:
            return .clear
        }
    }
}

enum DiffSide {
    case old
    case new
}
