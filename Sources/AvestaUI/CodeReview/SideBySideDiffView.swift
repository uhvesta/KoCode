import AvestaCore
import SwiftUI

struct SideBySideDiffView: View {
    let session: CodeReviewFlowFeature.CodeReviewSessionState
    let navigation: CodeReviewNavigationState
    let previousChange: () -> Void
    let nextChange: () -> Void
    var selectedLine: CodeReviewFlowFeature.PendingLine? = nil
    var commentText = ""
    var onSelectLine: (FileDiff, DiffLine) -> Void = { _, _ in }
    var onCommentTextChanged: (String) -> Void = { _ in }
    var onSaveComment: () -> Void = {}
    var onCancelComment: () -> Void = {}
    var onDeleteComment: (UUID) -> Void = { _ in }

    var body: some View {
        if let file = session.activeFile {
            VStack(spacing: 0) {
                fileHeader(file: file)
                Divider()

                switch session.diffMode {
                case .file:
                    FullFileView(
                        session: session,
                        file: file,
                        gitFile: gitFile(for: file),
                        navigation: navigation,
                        previousChange: previousChange,
                        nextChange: nextChange,
                        selectedLine: selectedLine,
                        commentText: commentText,
                        onSelectLine: onSelectLine,
                        onCommentTextChanged: onCommentTextChanged,
                        onSaveComment: onSaveComment,
                        onCancelComment: onCancelComment,
                        onDeleteComment: onDeleteComment
                    )
                case .unified:
                    unifiedBody(file: file)
                case .split:
                    splitBody(file: file)
                }
            }
        } else {
            ContentUnavailableView("No File Selected", systemImage: "doc.text")
        }
    }

    private func fileHeader(file: FileDiff) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: file.status))
                .foregroundStyle(.secondary)
            Text(file.path)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(summary(for: file))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func unifiedBody(file: FileDiff) -> some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(file.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            hunkHeader(hunk)
                            ForEach(hunk.lines) { line in
                                VStack(alignment: .leading, spacing: 0) {
                                    DiffLineView(
                                        line: line,
                                        side: line.kind == .removed ? .old : .new,
                                        filePath: file.path,
                                        isFocused: isFocused(line),
                                        isLastTurnChange: isLastTurn(line, in: file),
                                        showsAddComment: isCommentable(line, in: file),
                                        addComment: { onSelectLine(file, line) }
                                    )
                                    inlineContent(after: line, in: file)
                                }
                            }
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

    private func splitBody(file: FileDiff) -> some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(file.hunks) { hunk in
                        VStack(alignment: .leading, spacing: 0) {
                            hunkHeader(hunk)
                            splitPane(for: file, hunk: hunk, minWidth: proxy.size.width)
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

    private func splitPane(for file: FileDiff, hunk: DiffHunk, minWidth: CGFloat) -> some View {
        Group {
            switch file.status {
            case .added:
                DiffPane(
                    lines: hunk.lines,
                    side: .new,
                    file: file,
                    session: session,
                    navigation: navigation,
                    selectedLine: selectedLine,
                    commentText: commentText,
                    onSelectLine: onSelectLine,
                    onCommentTextChanged: onCommentTextChanged,
                    onSaveComment: onSaveComment,
                    onCancelComment: onCancelComment,
                    onDeleteComment: onDeleteComment
                )
            case .deleted:
                DiffPane(lines: hunk.lines, side: .old, file: nil, session: session, navigation: navigation)
            case .modified, .renamed:
                HStack(alignment: .top, spacing: 0) {
                    DiffPane(lines: hunk.lines, side: .old, file: nil, session: session, navigation: navigation)
                    Divider()
                    DiffPane(
                        lines: hunk.lines,
                        side: .new,
                        file: file,
                        session: session,
                        navigation: navigation,
                        selectedLine: selectedLine,
                        commentText: commentText,
                        onSelectLine: onSelectLine,
                        onCommentTextChanged: onCommentTextChanged,
                        onSaveComment: onSaveComment,
                        onCancelComment: onCancelComment,
                        onDeleteComment: onDeleteComment
                    )
                }
            }
        }
        .frame(minWidth: minWidth, alignment: .leading)
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)
    }

    private func inlineContent(after line: DiffLine, in file: FileDiff) -> some View {
        InlineCommentStack(
            comments: comments(for: line, in: file),
            selectedLine: selectedLine,
            file: file,
            line: line,
            commentText: commentText,
            onCommentTextChanged: onCommentTextChanged,
            onSaveComment: onSaveComment,
            onCancelComment: onCancelComment,
            onSelectLine: onSelectLine,
            onDeleteComment: onDeleteComment
        )
    }

    private func comments(for line: DiffLine, in file: FileDiff) -> [ReviewComment] {
        guard let lineNumber = line.newLineNumber,
              file.changedNewLineNumbers.contains(lineNumber)
        else { return [] }
        return session.comments
            .filter { $0.fileID == file.id && $0.startLine == lineNumber }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func isFocused(_ line: DiffLine) -> Bool {
        guard let lineNumber = line.newLineNumber,
              let focused = navigation.focusedChange
        else { return false }
        return focused.startLine...focused.endLine ~= lineNumber
    }

    private func isLastTurn(_ line: DiffLine, in file: FileDiff) -> Bool {
        guard session.scope == .lastTurnChanges,
              let lineNumber = line.newLineNumber
        else { return false }
        return file.changedNewLineNumbers.contains(lineNumber)
    }

    private func isCommentable(_ line: DiffLine, in file: FileDiff) -> Bool {
        guard let lineNumber = line.newLineNumber,
              line.kind == .added
        else { return false }
        return file.changedNewLineNumbers.contains(lineNumber)
    }

    private func gitFile(for file: FileDiff) -> FileDiff? {
        guard session.scope == .lastTurnChanges else { return file }
        return session.files.first { $0.path == file.path }
    }

    private func icon(for status: FileStatus) -> String {
        switch status {
        case .added: return "plus.circle"
        case .modified: return "circle"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        }
    }

    private func summary(for file: FileDiff) -> String {
        if file.status == .added {
            return "Added +\(file.addedLineCount)"
        }
        return "+\(file.addedLineCount)  -\(file.removedLineCount)"
    }
}

private struct FullFileView: View {
    let session: CodeReviewFlowFeature.CodeReviewSessionState
    let file: FileDiff
    let gitFile: FileDiff?
    let navigation: CodeReviewNavigationState
    let previousChange: () -> Void
    let nextChange: () -> Void
    let selectedLine: CodeReviewFlowFeature.PendingLine?
    let commentText: String
    var onSelectLine: (FileDiff, DiffLine) -> Void
    var onCommentTextChanged: (String) -> Void
    var onSaveComment: () -> Void
    var onCancelComment: () -> Void
    var onDeleteComment: (UUID) -> Void

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
                                    VStack(alignment: .leading, spacing: 0) {
                                        FullFileLineView(
                                            line: line,
                                            showsAddComment: line.isActiveScopeChange,
                                            addComment: {
                                                onSelectLine(file, DiffLine(
                                                    kind: line.kind ?? .context,
                                                    oldLineNumber: nil,
                                                    newLineNumber: line.number,
                                                    content: line.plainContent
                                                ))
                                            }
                                        )
                                        .id(line.number)

                                        InlineCommentStack(
                                            comments: comments(for: line),
                                            selectedLine: selectedLine,
                                            file: file,
                                            line: DiffLine(
                                                kind: line.kind ?? .context,
                                                oldLineNumber: nil,
                                                newLineNumber: line.number,
                                                content: line.plainContent
                                            ),
                                            commentText: commentText,
                                            onCommentTextChanged: onCommentTextChanged,
                                            onSaveComment: onSaveComment,
                                            onCancelComment: onCancelComment,
                                            onSelectLine: onSelectLine,
                                            onDeleteComment: onDeleteComment
                                        )
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
                Image(systemName: "chevron.up")
                    .frame(width: 22, height: 22)
            }
            .accessibilityLabel("Previous Change")
            .help("Previous Change")
            .disabled(navigation.focusedChangeIndex <= 0 || display.changes.isEmpty)

            Button {
                nextChange()
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 22, height: 22)
            }
            .accessibilityLabel("Next Change")
            .help("Next Change")
            .disabled(display.changes.isEmpty || navigation.focusedChangeIndex >= display.changes.count - 1)

            Text(display.changes.isEmpty ? "No changes in file" : navigation.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func comments(for line: FullFileLine) -> [ReviewComment] {
        guard line.isActiveScopeChange else { return [] }
        return session.comments
            .filter { $0.fileID == file.id && $0.startLine == line.number }
            .sorted { $0.createdAt < $1.createdAt }
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

        let gitChangeFile = gitFile ?? file
        var changedLines: [Int: DiffLineKind] = [:]
        for line in gitChangeFile.hunks.flatMap(\.lines) {
            guard let number = line.newLineNumber else { continue }
            changedLines[number] = line.kind
        }

        let activeScopeLines = file.changedNewLineNumbers
        let highlightedLines = SwiftSyntaxHighlighter.highlightedLines(for: content, path: file.path)
        let lines = highlightedLines.map { highlightedLine in
            let lineNumber = highlightedLine.lineNumber
            let plainContent = String(highlightedLine.content.characters)
            let kind = changedLines[lineNumber]
            return FullFileLine(
                number: lineNumber,
                content: plainContent.isEmpty ? AttributedString(" ") : highlightedLine.content,
                plainContent: plainContent,
                kind: kind,
                isFocused: displayFocus(for: lineNumber),
                isLastTurnChange: session.scope == .lastTurnChanges && activeScopeLines.contains(lineNumber),
                isActiveScopeChange: activeScopeLines.contains(lineNumber)
            )
        }
        return FullFileDisplay(lines: lines, changes: CodeReviewChangeNavigation.changes(in: file))
    }

    private func displayFocus(for lineNumber: Int) -> Bool {
        guard let focused = navigation.focusedChange else { return false }
        return focused.startLine...focused.endLine ~= lineNumber
    }
}

private struct FullFileDisplay {
    let lines: [FullFileLine]
    let changes: [CodeReviewChangeRange]
}

private struct FullFileLine: Identifiable {
    let number: Int
    let content: AttributedString
    let plainContent: String
    let kind: DiffLineKind?
    let isFocused: Bool
    let isLastTurnChange: Bool
    let isActiveScopeChange: Bool

    var id: Int { number }
}

private struct FullFileLineView: View {
    let line: FullFileLine
    var showsAddComment = false
    var addComment: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Text(String(line.number))
                .font(.custom("Menlo", size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 10)

            Text(line.content)
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
            if line.isFocused || line.isLastTurnChange {
                Rectangle()
                    .fill(line.isFocused ? Color.accentColor : Color.orange.opacity(0.85))
                    .frame(width: 3)
            }
        }
    }

    private var background: Color {
        if line.isLastTurnChange {
            return Color(red: 0.16, green: 0.11, blue: 0.04)
        }
        switch line.kind {
        case .added:
            return Color(red: 0.04, green: 0.12, blue: 0.07)
        case .removed:
            return Color(red: 0.15, green: 0.06, blue: 0.06)
        case .context, nil:
            return .clear
        }
    }
}

private struct DiffPane: View {
    let lines: [DiffLine]
    let side: DiffSide
    var file: FileDiff?
    let session: CodeReviewFlowFeature.CodeReviewSessionState
    let navigation: CodeReviewNavigationState
    var selectedLine: CodeReviewFlowFeature.PendingLine?
    var commentText = ""
    var onSelectLine: (FileDiff, DiffLine) -> Void = { _, _ in }
    var onCommentTextChanged: (String) -> Void = { _ in }
    var onSaveComment: () -> Void = {}
    var onCancelComment: () -> Void = {}
    var onDeleteComment: (UUID) -> Void = { _ in }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(linesForSide) { line in
                VStack(alignment: .leading, spacing: 0) {
                    DiffLineView(
                        line: line,
                        side: side,
                        filePath: file?.path,
                        isFocused: isFocused(line),
                        isLastTurnChange: isLastTurn(line),
                        showsAddComment: isCommentable(line),
                        addComment: {
                            guard let file else { return }
                            onSelectLine(file, line)
                        }
                    )
                    if let file {
                        InlineCommentStack(
                            comments: comments(for: line, in: file),
                            selectedLine: selectedLine,
                            file: file,
                            line: line,
                            commentText: commentText,
                            onCommentTextChanged: onCommentTextChanged,
                            onSaveComment: onSaveComment,
                            onCancelComment: onCancelComment,
                            onSelectLine: onSelectLine,
                            onDeleteComment: onDeleteComment
                        )
                    }
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

    private func isFocused(_ line: DiffLine) -> Bool {
        guard side == .new,
              let lineNumber = line.newLineNumber,
              let focused = navigation.focusedChange
        else { return false }
        return focused.startLine...focused.endLine ~= lineNumber
    }

    private func isLastTurn(_ line: DiffLine) -> Bool {
        guard side == .new,
              session.scope == .lastTurnChanges,
              let file,
              let lineNumber = line.newLineNumber
        else { return false }
        return file.changedNewLineNumbers.contains(lineNumber)
    }

    private func isCommentable(_ line: DiffLine) -> Bool {
        guard side == .new,
              let file,
              let lineNumber = line.newLineNumber,
              line.kind == .added
        else { return false }
        return file.changedNewLineNumbers.contains(lineNumber)
    }

    private func comments(for line: DiffLine, in file: FileDiff) -> [ReviewComment] {
        guard let lineNumber = line.newLineNumber,
              file.changedNewLineNumbers.contains(lineNumber)
        else { return [] }
        return session.comments
            .filter { $0.fileID == file.id && $0.startLine == lineNumber }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

private struct InlineCommentStack: View {
    let comments: [ReviewComment]
    let selectedLine: CodeReviewFlowFeature.PendingLine?
    let file: FileDiff
    let line: DiffLine
    let commentText: String
    var onCommentTextChanged: (String) -> Void
    var onSaveComment: () -> Void
    var onCancelComment: () -> Void
    var onSelectLine: (FileDiff, DiffLine) -> Void
    var onDeleteComment: (UUID) -> Void

    var body: some View {
        if !comments.isEmpty || isEditingLine {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(comments) { comment in
                    InlineCommentCard(
                        comment: comment,
                        edit: { onSelectLine(file, line) },
                        delete: { onDeleteComment(comment.id) }
                    )
                }

                if isEditingLine {
                    InlineCommentEditor(
                        text: commentText,
                        lineNumber: line.newLineNumber ?? 0,
                        textChanged: onCommentTextChanged,
                        save: onSaveComment,
                        cancel: onCancelComment
                    )
                }
            }
            .padding(.leading, 68)
            .padding(.vertical, 8)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var isEditingLine: Bool {
        guard let selectedLine,
              let lineNumber = line.newLineNumber
        else { return false }
        return selectedLine.fileID == file.id && selectedLine.lineNumber == lineNumber
    }
}

private struct InlineCommentEditor: View {
    let text: String
    let lineNumber: Int
    var textChanged: (String) -> Void
    var save: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: Binding(get: { text }, set: textChanged))
                .font(.body)
                .frame(height: 92)
                .accessibilityLabel("Comment Text")
                .accessibilityIdentifier("code-review-comment-text")
                .padding(6)

            Divider()

            HStack(spacing: 10) {
                Text("Commenting on line \(lineNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Comment", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
        }
    }
}

private struct InlineCommentCard: View {
    let comment: ReviewComment
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("You")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Edit", action: edit)
                Button("Delete", action: delete)
            }
            .buttonStyle(.borderless)

            Text(comment.text)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
