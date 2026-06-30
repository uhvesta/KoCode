import AvestaCore
import SwiftUI

struct SideBySideDiffView: View {
    let session: CodeReviewFlowFeature.CodeReviewSessionState
    let navigation: CodeReviewNavigationState
    let previousChange: () -> Void
    let nextChange: () -> Void
    var onSelectLine: (FileDiff, DiffLine) -> Void = { _, _ in }
    @State private var mode: CodeReviewDisplayMode = .file

    var body: some View {
        if let file = session.activeFile {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(file.path)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Picker("Display Mode", selection: $mode) {
                        ForEach(CodeReviewDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))

                Divider()

                switch mode {
                case .diff:
                    diffBody(file: file)
                case .file:
                    FullFileView(
                        session: session,
                        file: file,
                        navigation: navigation,
                        previousChange: previousChange,
                        nextChange: nextChange,
                        onSelectLine: onSelectLine
                    )
                }
            }
        } else {
            ContentUnavailableView("No File Selected", systemImage: "doc.text")
        }
    }

    private func diffBody(file: FileDiff) -> some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(file.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.vertical, 6)

                            diffPane(for: file, hunk: hunk, minWidth: proxy.size.width)
                        }
                    }

                    if file.hunks.isEmpty {
                        ContentUnavailableView("No Hunks", systemImage: "doc.text")
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .padding(.vertical)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func diffPane(for file: FileDiff, hunk: DiffHunk, minWidth: CGFloat) -> some View {
        switch file.status {
        case .added:
            DiffPane(lines: hunk.lines, side: .new, file: file, onSelectLine: onSelectLine)
                .frame(minWidth: minWidth, alignment: .leading)
        case .deleted:
            DiffPane(lines: hunk.lines, side: .old)
                .frame(minWidth: minWidth, alignment: .leading)
        case .modified, .renamed:
            HStack(alignment: .top, spacing: 0) {
                DiffPane(lines: hunk.lines, side: .old)
                Divider()
                DiffPane(lines: hunk.lines, side: .new, file: file, onSelectLine: onSelectLine)
            }
        }
    }
}

private enum CodeReviewDisplayMode: String, CaseIterable, Identifiable {
    case file
    case diff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: return "File"
        case .diff: return "Diff"
        }
    }
}

private struct FullFileView: View {
    let session: CodeReviewFlowFeature.CodeReviewSessionState
    let file: FileDiff
    let navigation: CodeReviewNavigationState
    let previousChange: () -> Void
    let nextChange: () -> Void
    var onSelectLine: (FileDiff, DiffLine) -> Void

    init(
        session: CodeReviewFlowFeature.CodeReviewSessionState,
        file: FileDiff,
        navigation: CodeReviewNavigationState,
        previousChange: @escaping () -> Void,
        nextChange: @escaping () -> Void,
        onSelectLine: @escaping (FileDiff, DiffLine) -> Void
    ) {
        self.session = session
        self.file = file
        self.navigation = navigation
        self.previousChange = previousChange
        self.nextChange = nextChange
        self.onSelectLine = onSelectLine
    }

    var body: some View {
        GeometryReader { proxy in
            if let display = fullFileDisplay {
                VStack(spacing: 0) {
                    changeNavigator(display: display)
                    Divider()

                    ScrollViewReader { scrollProxy in
                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(display.lines) { line in
                                    FullFileLineView(
                                        line: line,
                                        isFocused: display.focusedLineNumbers(for: navigation.focusedChangeIndex).contains(line.number)
                                    )
                                    .id(line.number)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        let diffLine = DiffLine(
                                            kind: line.kind ?? .context,
                                            oldLineNumber: nil,
                                            newLineNumber: line.number,
                                            content: line.plainContent
                                        )
                                        onSelectLine(file, diffLine)
                                    }
                                }
                            }
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .onAppear {
                            scrollToFocusedChange(display: display, proxy: scrollProxy)
                        }
                        .onChange(of: navigation.focusedChangeIndex) { _, _ in
                            scrollToFocusedChange(display: display, proxy: scrollProxy)
                        }
                    }
                }
            } else {
                ContentUnavailableView("File Not Available", systemImage: "doc.text")
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func changeNavigator(display: FullFileDisplay) -> some View {
        HStack(spacing: 8) {
            Button {
                previousChange()
            } label: {
                Label("Previous", systemImage: "chevron.up")
            }
            .accessibilityLabel("Previous Change")
            .help("Previous Change")
            .disabled(navigation.focusedChangeIndex <= 0 || display.changes.isEmpty)

            Button {
                nextChange()
            } label: {
                Label("Next", systemImage: "chevron.down")
            }
            .accessibilityLabel("Next Change")
            .help("Next Change")
            .disabled(display.changes.isEmpty || navigation.focusedChangeIndex >= display.changes.count - 1)

            Text(changeStatus(display: display))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func changeStatus(display: FullFileDisplay) -> String {
        guard !display.changes.isEmpty else { return "No changes in file" }
        return navigation.statusText
    }

    private func scrollToFocusedChange(display: FullFileDisplay, proxy: ScrollViewProxy) {
        guard display.changes.indices.contains(navigation.focusedChangeIndex) else { return }
        let line = display.changes[navigation.focusedChangeIndex].startLine
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(line, anchor: .center)
            }
        }
    }

    private var fullFileDisplay: FullFileDisplay? {
        guard file.status != .deleted else { return nil }
        let repoURL = session.repoPath.isFileURL
            ? session.repoPath
            : URL(fileURLWithPath: session.repoPath.path, isDirectory: true)
        let url = repoURL.appendingPathComponent(file.path, isDirectory: false)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var changedLines: [Int: DiffLineKind] = [:]
        for line in file.hunks.flatMap(\.lines) {
            guard let number = line.newLineNumber else { continue }
            changedLines[number] = line.kind
        }
        let highlightedLines = SwiftSyntaxHighlighter.highlightedLines(for: content, path: file.path)
        let lines = highlightedLines.map { line in
            let plainContent = String(line.content.characters)
            return FullFileLine(
                number: line.lineNumber,
                content: plainContent.isEmpty ? AttributedString(" ") : line.content,
                plainContent: plainContent,
                kind: changedLines[line.lineNumber]
            )
        }
        return FullFileDisplay(lines: lines, changes: CodeReviewChangeNavigation.changes(in: file))
    }
}

private struct FullFileDisplay {
    let lines: [FullFileLine]
    let changes: [CodeReviewChangeRange]

    func focusedLineNumbers(for index: Int) -> Set<Int> {
        guard changes.indices.contains(index) else { return [] }
        return Set(changes[index].startLine...changes[index].endLine)
    }
}

private struct FullFileLine: Identifiable {
    let number: Int
    let content: AttributedString
    let plainContent: String
    let kind: DiffLineKind?

    var id: Int { number }
}

private struct FullFileLineView: View {
    let line: FullFileLine
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(String(line.number))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
                .padding(.trailing, 10)

            Text(line.content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.trailing, 12)
        .background(background)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
    }

    private var background: Color {
        if isFocused {
            return Color.accentColor.opacity(0.18)
        }
        switch line.kind {
        case .added:
            return Color.green.opacity(0.14)
        case .removed:
            return Color.red.opacity(0.14)
        case .context, nil:
            return .clear
        }
    }
}

private struct DiffPane: View {
    let lines: [DiffLine]
    let side: DiffSide
    var file: FileDiff?
    var onSelectLine: (FileDiff, DiffLine) -> Void = { _, _ in }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(linesForSide) { line in
                DiffLineView(line: line, side: side, filePath: file?.path)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard side == .new, let file, line.newLineNumber != nil else { return }
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
