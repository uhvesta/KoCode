import AvestaCore
import SwiftUI

struct SideBySideDiffView: View {
    let session: CodeReviewSession
    var onSelectLine: (FileDiff, DiffLine) -> Void = { _, _ in }

    var body: some View {
        if let file = session.activeFile {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(file.path)
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(file.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.vertical, 6)

                            HStack(alignment: .top, spacing: 0) {
                                DiffPane(lines: hunk.lines, side: .old)
                                Divider()
                                DiffPane(lines: hunk.lines, side: .new, session: session, file: file, onSelectLine: onSelectLine)
                            }
                        }
                    }
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("No File Selected", systemImage: "doc.text")
        }
    }
}

private struct DiffPane: View {
    let lines: [DiffLine]
    let side: DiffSide
    var session: CodeReviewSession?
    var file: FileDiff?
    var onSelectLine: (FileDiff, DiffLine) -> Void = { _, _ in }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(linesForSide) { line in
                DiffLineView(line: line, side: side)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard side == .new, let session, let file, let lineNumber = line.newLineNumber else { return }
                        _ = session
                        _ = lineNumber
                        onSelectLine(file, line)
                    }
            }
        }
        .frame(minWidth: 360, alignment: .leading)
    }

    private var linesForSide: [DiffLine] {
        lines.filter { line in
            switch side {
            case .old:
                line.kind != .added
            case .new:
                line.kind != .removed
            }
        }
    }
}
