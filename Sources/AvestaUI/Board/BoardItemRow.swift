import AvestaCore
import SwiftUI

struct BoardItemRow: View {
    let item: BoardItem
    let paste: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let reviewCommentCount {
                    Text("\(reviewCommentCount) \(reviewCommentCount == 1 ? "comment" : "comments")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy Board Item")
                .accessibilityIdentifier("board-copy-item")
                .help("Copy")

                Button(action: paste) {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Paste Board Item to Terminal")
                .accessibilityIdentifier("board-paste-item-to-terminal")
                .help("Paste to Terminal")
            }

            Text(item.content)
                .font(.system(size: 11, design: .monospaced))
                .lineSpacing(2)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("board-item-row")
        .onTapGesture {
            isExpanded.toggle()
        }
        .padding(.vertical, 6)
    }

    private var collapsedLineLimit: Int {
        reviewCommentCount == nil ? 6 : 18
    }

    private var reviewCommentCount: Int? {
        guard item.source.hasPrefix("Code Review:") else { return nil }
        let count = item.content
            .split(separator: "\n")
            .filter { line in
                line.hasPrefix("### Line ") || line.hasPrefix("### Lines ")
            }
            .count
        return count > 0 ? count : nil
    }
}
