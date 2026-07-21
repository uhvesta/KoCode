import AvestaCore
import AppKit
import SwiftUI

struct WorkspaceReviewView: View {
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    @State private var selectedFileID: String?
    @State private var composer: AnnotationComposerState?
    @State private var relativeBranch = ""
    @State private var activeHunkID: String?
    @State private var oldHighlights: [Int: AttributedString] = [:]
    @State private var newHighlights: [Int: AttributedString] = [:]
    @State private var selectedDocument: ReviewDiffDocument?
    @State private var lineSelection: ReviewLineSelection?
    @State private var showingComments = false
    @State private var inlineCommentFocus: ReviewCommentFocus?

    private var state: WorkspaceReviewState { model.reviewStates[workspace.id] ?? WorkspaceReviewState(workspaceID: workspace.id) }
    private var files: [WorkspaceFileDiff] {
        state.files.filter { state.repositoryFilter == nil || $0.repositoryID == state.repositoryFilter }
    }
    private var selectedFile: WorkspaceFileDiff? { files.first { $0.id == selectedFileID } ?? files.first }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                fileNavigator.frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
                Divider()
                if let file = selectedFile {
                    diffContent(currentDocument(for: file)).id(file.id)
                }
                else { ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("The selected baseline has no changed files.")) }
            }
        }
        .sheet(item: $composer) { state in
            AnnotationComposer(model: model, workspace: workspace, state: state) { annotation in
                lineSelection = nil
                revealComment(annotation)
            }
        }
        .sheet(isPresented: $showingComments) {
            ReviewCommentsSheet(
                model: model,
                workspace: workspace,
                canReveal: canReveal,
                onReveal: revealComment
            )
        }
        .onAppear {
            synchronizeRelativeBranch()
            synchronizeSelectedDocument()
        }
        .onChange(of: state.baseline.storageValue) { _, _ in synchronizeRelativeBranch() }
        .onChange(of: selectedFile?.diff.id) { _, _ in synchronizeSelectedDocument() }
        .task(id: highlightTaskIdentity) { await loadHighlighting() }
        .onExitCommand { lineSelection = nil }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Repository", selection: Binding(get: { state.repositoryFilter }, set: { value in Task { await model.setReviewRepositoryFilter(workspaceID: workspace.id, repositoryID: value) } })) {
                Text("All Repositories").tag(UUID?.none)
                ForEach(workspace.repositories) { Text($0.name).tag(UUID?.some($0.id)) }
            }.frame(maxWidth: 210)
            baselinePicker.frame(maxWidth: 220)
            TextField("Relative branch", text: $relativeBranch).textFieldStyle(.roundedBorder).frame(width: 150)
            Button("Compare") { Task { await model.setReviewBaseline(workspaceID: workspace.id, baseline: .branch(relativeBranch.trimmingCharacters(in: .whitespacesAndNewlines))) } }.disabled(relativeBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { Task { await model.refreshReview(workspaceID: workspace.id) } } label: { if state.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") } }.disabled(state.isRefreshing)
            Picker("Mode", selection: Binding(get: { state.mode }, set: { mode in Task { await model.setReviewMode(workspaceID: workspace.id, mode: mode) } })) {
                Text("Unified").tag(ReviewDisplayMode.unified)
                Text("Split").tag(ReviewDisplayMode.split)
                Text("Full File").tag(ReviewDisplayMode.fullFile)
            }.pickerStyle(.segmented).frame(width: 250)
            Spacer()
            Text("\(files.count) files  +\(state.additions)  −\(state.deletions)").font(.caption).foregroundStyle(.secondary)
            Button {
                showingComments = true
            } label: {
                Label("Comments \(state.annotations.count)", systemImage: "text.bubble")
            }
            Button("Finish Review") { Task { await model.finishReview(workspaceID: workspace.id) } }
        }.padding(8)
    }

    private var baselinePicker: some View {
        Picker("Baseline", selection: Binding(get: { state.baseline.storageValue }, set: { value in Task { await model.setReviewBaseline(workspaceID: workspace.id, baseline: ReviewBaseline(storageValue: value)) } })) {
            Text("Current vs HEAD").tag("head")
            if case .branch(let reference) = state.baseline { Text("Relative to \(reference)").tag("branch:\(reference)") }
            Text("Since Session Start").tag("activity")
            Text("Since Last Review").tag("last-review")
            if !state.historicalSnapshots.isEmpty {
                Divider()
                ForEach(state.historicalSnapshots) { snapshot in Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)).tag("snapshot:\(snapshot.id.uuidString)") }
            }
        }
    }

    private var fileNavigator: some View {
        List(selection: $selectedFileID) {
            ForEach(Dictionary(grouping: files, by: \WorkspaceFileDiff.repositoryName).keys.sorted(), id: \.self) { repositoryName in
                Section(repositoryName) {
                    ForEach(files.filter { $0.repositoryName == repositoryName }) { file in
                        HStack(spacing: 7) {
                            Image(systemName: statusIcon(file.diff.status)).foregroundStyle(statusColor(file.diff.status))
                            Text(file.diff.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("+\(file.diff.addedLineCount) −\(file.diff.removedLineCount)").font(.caption2).foregroundStyle(.secondary)
                            let count = state.annotations.filter { $0.repositoryID == file.repositoryID && $0.filePath == file.diff.path }.count
                            if count > 0 { Text("\(count)").font(.caption2).padding(4).background(.quaternary).clipShape(Circle()) }
                        }.tag(file.id)
                    }
                }
            }
            let outdated = state.annotations.filter(\.isOutdated)
            if !outdated.isEmpty {
                Section("Outdated") { ForEach(outdated) { Text("\($0.filePath):\($0.startLine) — \($0.userText)").font(.caption) } }
            }
            if !state.repositoryErrors.isEmpty {
                Section("Repository Errors") {
                    ForEach(workspace.repositories.filter { state.repositoryErrors[$0.id] != nil }) { repository in
                        VStack(alignment: .leading) { Text(repository.name).fontWeight(.semibold); Text(state.repositoryErrors[repository.id] ?? "").font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func diffContent(_ document: ReviewDiffDocument) -> some View {
        let file = document.file
        VStack(spacing: 0) {
            HStack {
                Text(file.repositoryName).foregroundStyle(.secondary)
                if let oldPath = file.diff.oldPath { Text(oldPath).strikethrough().foregroundStyle(.secondary); Image(systemName: "arrow.right") }
                Text(file.diff.path).fontWeight(.semibold)
                Text(file.diff.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                Text("+\(file.diff.addedLineCount) −\(file.diff.removedLineCount)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let selection = activeSelection(for: file) {
                    Text("\(selection.lineCount) line\(selection.lineCount == 1 ? "" : "s") selected")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        beginAnnotation(document: document, selection: selection)
                    } label: {
                        Label("Add Comment", systemImage: "plus.bubble")
                    }
                    Button { lineSelection = nil } label: {
                        Image(systemName: "xmark").accessibilityLabel("Clear line selection")
                    }
                } else {
                    Text("Click a line · Shift-click to select a range")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let position = activeChangePosition { Text("Change \(position.current) of \(position.total)").font(.caption).foregroundStyle(.secondary) }
                Button("Previous Change") { selectRelativeHunk(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
                Button("Next Change") { selectRelativeHunk(1) }.keyboardShortcut(.downArrow, modifiers: .option)
            }.padding(8)
            Divider()
            switch state.mode {
            case .unified: UnifiedDiff(model: model, document: document, annotations: annotations(for: file), selection: lineSelection, inlineCommentFocus: inlineCommentFocus, activeHunkID: activeHunkID, oldHighlights: oldHighlights, newHighlights: newHighlights, select: selectLine, toggleComments: toggleInlineComments)
            case .split: SplitDiff(model: model, document: document, annotations: annotations(for: file), selection: lineSelection, inlineCommentFocus: inlineCommentFocus, activeHunkID: activeHunkID, oldHighlights: oldHighlights, newHighlights: newHighlights, select: selectLine, toggleComments: toggleInlineComments)
            case .fullFile: FullFileDiff(model: model, document: document, annotations: annotations(for: file), selection: lineSelection, inlineCommentFocus: inlineCommentFocus, activeHunkID: activeHunkID, oldHighlights: oldHighlights, newHighlights: newHighlights, select: selectLine, toggleComments: toggleInlineComments)
            }
        }
    }

    private func annotations(for file: WorkspaceFileDiff) -> [ReviewAnnotation] { state.annotations.filter { !$0.isOutdated && $0.repositoryID == file.repositoryID && $0.filePath == file.diff.path } }
    private func synchronizeRelativeBranch() {
        if case .branch(let reference) = state.baseline {
            relativeBranch = reference
        } else if relativeBranch.isEmpty {
            relativeBranch = model.defaultBaseBranch
        }
    }
    private func selectLine(file: WorkspaceFileDiff, line: DiffLine, side: DiffSide) {
        guard let lineNumber = side == .old ? line.oldLineNumber : line.newLineNumber else { return }
        // `currentEvent` can be nil by the time SwiftUI invokes the gesture.
        // The class-level modifier state keeps Shift-click range selection
        // reliable across both SwiftUI and AppKit-hosted review surfaces.
        let shouldExtend = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            || NSEvent.modifierFlags.contains(.shift)
        lineSelection = ReviewLineSelection.selectionAfterClick(
            current: lineSelection,
            fileID: file.id,
            side: side,
            line: lineNumber,
            extending: shouldExtend
        )
    }
    private func activeSelection(for file: WorkspaceFileDiff) -> ReviewLineSelection? {
        guard lineSelection?.fileID == file.id else { return nil }
        return lineSelection
    }
    private func toggleInlineComments(file: WorkspaceFileDiff, side: DiffSide, line: Int) {
        let focus = ReviewCommentFocus(repositoryID: file.repositoryID, filePath: file.diff.path, side: side, line: line)
        inlineCommentFocus = inlineCommentFocus == focus ? nil : focus
    }
    private func canReveal(_ annotation: ReviewAnnotation) -> Bool {
        !annotation.isOutdated && files.contains { $0.repositoryID == annotation.repositoryID && $0.diff.path == annotation.filePath }
    }
    private func revealComment(_ annotation: ReviewAnnotation) {
        guard let file = files.first(where: { $0.repositoryID == annotation.repositoryID && $0.diff.path == annotation.filePath }) else { return }
        selectedFileID = file.id
        inlineCommentFocus = ReviewCommentFocus(
            repositoryID: annotation.repositoryID,
            filePath: annotation.filePath,
            side: annotation.side,
            line: annotation.startLine
        )
        activeHunkID = ReviewDiffDocument(file: file).hunkID(
            side: annotation.side,
            intersecting: annotation.startLine...annotation.endLine
        )
    }
    private func beginAnnotation(document: ReviewDiffDocument, selection: ReviewLineSelection) {
        composer = AnnotationComposerState(
            file: document.file,
            side: selection.side,
            startLine: selection.lines.lowerBound,
            endLine: selection.lines.upperBound,
            selectedCode: document.sourceExcerpt(side: selection.side, lines: selection.lines),
            context: document.surroundingContext(side: selection.side, lines: selection.lines)
        )
    }
    private var allChanges: [(fileID: String, hunkID: String)] {
        files.flatMap { file in
            file.diff.hunks.enumerated().map {
                (file.id, ReviewDiffHunk.stableID(for: $0.element, ordinal: $0.offset))
            }
        }
    }
    private var activeChangePosition: (current: Int, total: Int)? {
        let changes = allChanges
        guard !changes.isEmpty else { return nil }
        let index = changes.firstIndex { $0.fileID == selectedFile?.id && $0.hunkID == activeHunkID }
            ?? changes.firstIndex { $0.fileID == selectedFile?.id }
            ?? 0
        return (index + 1, changes.count)
    }
    private func selectRelativeHunk(_ offset: Int) {
        let changes = allChanges
        guard !changes.isEmpty else { return }
        let current = changes.firstIndex { $0.fileID == selectedFile?.id && $0.hunkID == activeHunkID }
            ?? changes.firstIndex { $0.fileID == selectedFile?.id }
            ?? 0
        let next = changes[(current + offset % changes.count + changes.count) % changes.count]
        selectedFileID = next.fileID
        activeHunkID = next.hunkID
    }
    private var highlightTaskIdentity: String {
        guard let file = selectedFile else { return "none" }
        return "\(file.id):\(file.oldContent.hashValue):\(file.newContent.hashValue)"
    }
    private func currentDocument(for file: WorkspaceFileDiff) -> ReviewDiffDocument {
        if let selectedDocument, selectedDocument.file.diff.id == file.diff.id { return selectedDocument }
        return ReviewDiffDocument(file: file)
    }
    private func synchronizeSelectedDocument() {
        guard let file = selectedFile else {
            selectedDocument = nil
            activeHunkID = nil
            return
        }
        let document = ReviewDiffDocument(file: file)
        selectedDocument = document
        if lineSelection?.fileID != file.id { lineSelection = nil }
        if inlineCommentFocus.map({ $0.repositoryID != file.repositoryID || $0.filePath != file.diff.path }) == true { inlineCommentFocus = nil }
        if !document.hunks.contains(where: { $0.id == activeHunkID }) {
            activeHunkID = document.firstHunkID
        }
    }
    private func loadHighlighting() async {
        guard let file = selectedFile else { oldHighlights = [:]; newHighlights = [:]; return }
        oldHighlights = Dictionary(uniqueKeysWithValues: SyntaxHighlighter.plainLines(for: file.oldContent).map { ($0.lineNumber, $0.content) })
        newHighlights = Dictionary(uniqueKeysWithValues: SyntaxHighlighter.plainLines(for: file.newContent).map { ($0.lineNumber, $0.content) })
        let path = file.diff.path
        let oldPath = file.diff.oldPath ?? path
        let oldSource = file.oldContent
        let newSource = file.newContent
        let result = await Task.detached(priority: .userInitiated) {
            (
                SyntaxHighlighter.highlightedLines(for: oldSource, path: oldPath),
                SyntaxHighlighter.highlightedLines(for: newSource, path: path)
            )
        }.value
        guard !Task.isCancelled else { return }
        oldHighlights = Dictionary(uniqueKeysWithValues: result.0.map { ($0.lineNumber, $0.content) })
        newHighlights = Dictionary(uniqueKeysWithValues: result.1.map { ($0.lineNumber, $0.content) })
    }
    private func statusIcon(_ status: FileStatus) -> String { switch status { case .added: return "plus.circle"; case .deleted: return "minus.circle"; case .renamed: return "arrow.right.circle"; case .modified: return "pencil.circle" } }
    private func statusColor(_ status: FileStatus) -> Color { switch status { case .added: return .green; case .deleted: return .red; case .renamed: return .blue; case .modified: return .orange } }
}

private struct UnifiedDiff: View {
    let model: ApplicationModel
    let document: ReviewDiffDocument
    let annotations: [ReviewAnnotation]
    let selection: ReviewLineSelection?
    let inlineCommentFocus: ReviewCommentFocus?
    let activeHunkID: String?
    let oldHighlights: [Int: AttributedString]
    let newHighlights: [Int: AttributedString]
    let select: (WorkspaceFileDiff, DiffLine, DiffSide) -> Void
    let toggleComments: (WorkspaceFileDiff, DiffSide, Int) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.hunks) { hunk in
                            HunkHeader(title: hunk.header, isActive: hunk.id == activeHunkID).id(hunk.id)
                            ForEach(hunk.unifiedRows) { row in
                                VStack(spacing: 0) {
                                    let comments = rowAnnotations(side: row.sourceSide, lineNumber: row.sourceLineNumber)
                                    DiffRow(
                                        line: row.line,
                                        highlightedContent: highlighted(side: row.sourceSide, lineNumber: row.sourceLineNumber, fallback: row.line.content),
                                        annotationCount: comments.count,
                                        isSelected: isSelected(side: row.sourceSide, lineNumber: row.sourceLineNumber),
                                        openAnnotations: { if let line = row.sourceLineNumber { toggleComments(document.file, row.sourceSide, line) } }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { select(document.file, row.line, row.sourceSide) }
                                    if isExpanded(side: row.sourceSide, lineNumber: row.sourceLineNumber), !comments.isEmpty {
                                        InlineReviewThread(model: model, annotations: comments)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: max(geometry.size.width, 760), alignment: .leading)
                }
                .onAppear { scroll(to: activeHunkID, proxy: proxy) }
                .onChange(of: activeHunkID) { _, value in if let value { withAnimation { proxy.scrollTo(value, anchor: .top) } } }
            }
        }
    }

    private func highlighted(side: DiffSide, lineNumber: Int?, fallback: String) -> AttributedString {
        guard let lineNumber else { return AttributedString(fallback) }
        return (side == .old ? oldHighlights[lineNumber] : newHighlights[lineNumber]) ?? AttributedString(fallback)
    }
    private func rowAnnotations(side: DiffSide, lineNumber: Int?) -> [ReviewAnnotation] {
        guard let lineNumber else { return [] }
        return annotations.filter { $0.side == side && $0.startLine...$0.endLine ~= lineNumber }
    }
    private func isExpanded(side: DiffSide, lineNumber: Int?) -> Bool {
        guard let lineNumber else { return false }
        return inlineCommentFocus == ReviewCommentFocus(repositoryID: document.file.repositoryID, filePath: document.file.diff.path, side: side, line: lineNumber)
    }
    private func isSelected(side: DiffSide, lineNumber: Int?) -> Bool {
        guard let lineNumber else { return false }
        return selection?.contains(fileID: document.file.id, side: side, line: lineNumber) == true
    }
    private func scroll(to hunkID: String?, proxy: ScrollViewProxy) {
        guard let hunkID else { return }
        proxy.scrollTo(hunkID, anchor: .top)
    }
}

private struct SplitDiff: View {
    let model: ApplicationModel
    let document: ReviewDiffDocument
    let annotations: [ReviewAnnotation]
    let selection: ReviewLineSelection?
    let inlineCommentFocus: ReviewCommentFocus?
    let activeHunkID: String?
    let oldHighlights: [Int: AttributedString]
    let newHighlights: [Int: AttributedString]
    let select: (WorkspaceFileDiff, DiffLine, DiffSide) -> Void
    let toggleComments: (WorkspaceFileDiff, DiffSide, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Before").frame(maxWidth: .infinity)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1)
                Text("After").frame(maxWidth: .infinity)
            }
            .frame(height: 30)
            .font(.caption.bold()).background(.bar)
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(document.hunks) { hunk in
                                HunkHeader(title: hunk.header, isActive: hunk.id == activeHunkID).id(hunk.id)
                                ForEach(hunk.splitRows) { row in
                                    VStack(spacing: 0) {
                                        HStack(spacing: 0) {
                                            SplitCell(cell: row.old, highlightedContent: highlight(row.old), annotationCount: annotationCount(row.old), isSelected: isSelected(row.old), select: { line, side in select(document.file, line, side) }, openAnnotations: { if let cell = row.old { toggleComments(document.file, cell.side, cell.lineNumber) } })
                                            Divider()
                                            SplitCell(cell: row.new, highlightedContent: highlight(row.new), annotationCount: annotationCount(row.new), isSelected: isSelected(row.new), select: { line, side in select(document.file, line, side) }, openAnnotations: { if let cell = row.new { toggleComments(document.file, cell.side, cell.lineNumber) } })
                                        }
                                        .frame(height: 20)
                                        if isExpanded(row.old) || isExpanded(row.new) {
                                            HStack(spacing: 0) {
                                                inlineThread(row.old)
                                                Divider()
                                                inlineThread(row.new)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minWidth: max(geometry.size.width, 1_000), alignment: .leading)
                    }
                    .onAppear { if let activeHunkID { proxy.scrollTo(activeHunkID, anchor: .top) } }
                    .onChange(of: activeHunkID) { _, value in if let value { withAnimation { proxy.scrollTo(value, anchor: .top) } } }
                }
            }
        }
    }

    private func highlight(_ cell: DiffCell?) -> AttributedString {
        guard let cell else { return AttributedString("") }
        return (cell.side == .old ? oldHighlights[cell.lineNumber] : newHighlights[cell.lineNumber]) ?? AttributedString(cell.content)
    }
    private func annotationCount(_ cell: DiffCell?) -> Int {
        cellAnnotations(cell).count
    }
    private func cellAnnotations(_ cell: DiffCell?) -> [ReviewAnnotation] {
        guard let cell else { return [] }
        return annotations.filter { $0.side == cell.side && $0.startLine...$0.endLine ~= cell.lineNumber }
    }
    private func isSelected(_ cell: DiffCell?) -> Bool {
        guard let cell else { return false }
        return selection?.contains(fileID: document.file.id, side: cell.side, line: cell.lineNumber) == true
    }
    private func isExpanded(_ cell: DiffCell?) -> Bool {
        guard let cell else { return false }
        return inlineCommentFocus == ReviewCommentFocus(repositoryID: document.file.repositoryID, filePath: document.file.diff.path, side: cell.side, line: cell.lineNumber)
    }
    @ViewBuilder private func inlineThread(_ cell: DiffCell?) -> some View {
        if isExpanded(cell) {
            InlineReviewThread(model: model, annotations: cellAnnotations(cell)).frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 1)
        }
    }
}

private struct FullFileDiff: View {
    let model: ApplicationModel
    let document: ReviewDiffDocument
    let annotations: [ReviewAnnotation]
    let selection: ReviewLineSelection?
    let inlineCommentFocus: ReviewCommentFocus?
    let activeHunkID: String?
    let oldHighlights: [Int: AttributedString]
    let newHighlights: [Int: AttributedString]
    let select: (WorkspaceFileDiff, DiffLine, DiffSide) -> Void
    let toggleComments: (WorkspaceFileDiff, DiffSide, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if document.file.diff.status == .deleted {
                Label("Deleted file — showing baseline", systemImage: "trash")
                    .font(.caption.bold()).foregroundStyle(.red).padding(7).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.08))
            }
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(document.fullFileRows) { row in
                                switch row {
                                case .source(let source):
                                    VStack(spacing: 0) {
                                        let comments = rowAnnotations(side: source.side, line: source.lineNumber)
                                        FullFileSourceView(
                                            row: source,
                                            highlightedContent: highlight(source),
                                            annotationCount: comments.count,
                                            isSelected: selection?.contains(fileID: document.file.id, side: source.side, line: source.lineNumber) == true,
                                            select: { select(document.file, source.diffLine, source.side) },
                                            openAnnotations: { toggleComments(document.file, source.side, source.lineNumber) }
                                        )
                                        if isExpanded(side: source.side, line: source.lineNumber), !comments.isEmpty {
                                            InlineReviewThread(model: model, annotations: comments)
                                        }
                                    }.id(source.id)
                                case .deletion(let marker):
                                    FullFileDeletionView(
                                        model: model,
                                        marker: marker,
                                        oldHighlights: oldHighlights,
                                        annotations: annotations,
                                        selection: selection,
                                        inlineCommentFocus: inlineCommentFocus,
                                        fileID: document.file.id,
                                        repositoryID: document.file.repositoryID,
                                        filePath: document.file.diff.path,
                                        select: { select(document.file, $0, .old) },
                                        toggleComments: { toggleComments(document.file, .old, $0) }
                                    ).id(marker.id)
                                }
                            }
                        }
                        .frame(minWidth: max(geometry.size.width, 760), alignment: .leading)
                    }
                    .onAppear { scroll(to: activeHunkID, proxy: proxy) }
                    .onChange(of: activeHunkID) { _, value in scroll(to: value, proxy: proxy) }
                }
            }
        }
    }

    private func highlight(_ row: FullFileSourceRow) -> AttributedString {
        (row.side == .old ? oldHighlights[row.lineNumber] : newHighlights[row.lineNumber]) ?? AttributedString(row.content)
    }
    private func rowAnnotations(side: DiffSide, line: Int) -> [ReviewAnnotation] {
        annotations.filter { $0.side == side && $0.startLine...$0.endLine ~= line }
    }
    private func isExpanded(side: DiffSide, line: Int) -> Bool {
        inlineCommentFocus == ReviewCommentFocus(repositoryID: document.file.repositoryID, filePath: document.file.diff.path, side: side, line: line)
    }
    private func scroll(to hunkID: String?, proxy: ScrollViewProxy) {
        guard let hunkID, let target = document.fullFileTargetID(forHunkID: hunkID) else { return }
        withAnimation { proxy.scrollTo(target, anchor: .center) }
    }
}

private struct HunkHeader: View {
    let title: String
    let isActive: Bool
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.blue)
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(Color.blue.opacity(isActive ? 0.18 : 0.08))
            .overlay(alignment: .leading) { if isActive { Rectangle().fill(Color.accentColor).frame(width: 3) } }
    }
}

private struct DiffRow: View {
    let line: DiffLine
    let highlightedContent: AttributedString
    let annotationCount: Int
    let isSelected: Bool
    let openAnnotations: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            gutterText(line.oldLineNumber).frame(width: 48, alignment: .trailing)
            gutterText(line.newLineNumber).frame(width: 48, alignment: .trailing)
            Text(marker).frame(width: 24)
            annotationIndicator.frame(width: 24)
            Text(highlightedContent).textSelection(.enabled).padding(.horizontal, 6)
            Spacer(minLength: 20)
        }
        .frame(minHeight: 20)
        .font(.system(size: 12, design: .monospaced)).lineLimit(1)
        .background(background)
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(line.kind.rawValue), line \(line.newLineNumber ?? line.oldLineNumber ?? 0), \(line.content)")
    }
    private var marker: String { line.kind == .added ? "+" : line.kind == .removed ? "−" : " " }
    private var background: Color {
        if isSelected { return .accentColor.opacity(0.24) }
        return line.kind == .added ? .green.opacity(0.14) : line.kind == .removed ? .red.opacity(0.14) : .clear
    }
    private var accent: Color { line.kind == .added ? .green.opacity(0.8) : line.kind == .removed ? .red.opacity(0.8) : .clear }
    private func gutterText(_ number: Int?) -> some View { Text(number.map(String.init) ?? "").foregroundStyle(.secondary).padding(.trailing, 6) }
    @ViewBuilder private var annotationIndicator: some View {
        if annotationCount > 0 {
            Button(action: openAnnotations) {
                Image(systemName: "text.bubble.fill").font(.caption2).foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(annotationCount) comment\(annotationCount == 1 ? "" : "s")")
        }
        else { Color.clear }
    }
}

private struct SplitCell: View {
    let cell: DiffCell?
    let highlightedContent: AttributedString
    let annotationCount: Int
    let isSelected: Bool
    let select: (DiffLine, DiffSide) -> Void
    let openAnnotations: () -> Void
    var body: some View {
        Group {
            if let cell {
                HStack(spacing: 0) {
                    Text(String(cell.lineNumber)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing).padding(.trailing, 6)
                    Text(cell.kind == .added ? "+" : cell.kind == .removed ? "−" : " ").frame(width: 22)
                    Group {
                        if annotationCount > 0 {
                            Button(action: openAnnotations) { Image(systemName: "text.bubble.fill").foregroundStyle(.blue) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View \(annotationCount) comment\(annotationCount == 1 ? "" : "s")")
                        } else { Color.clear }
                    }.frame(width: 22)
                    Text(highlightedContent).textSelection(.enabled).padding(.horizontal, 5)
                    Spacer(minLength: 12)
                }
                .background(isSelected ? Color.accentColor.opacity(0.24) : cell.kind == .added ? Color.green.opacity(0.14) : cell.kind == .removed ? Color.red.opacity(0.14) : .clear)
                .contentShape(Rectangle()).onTapGesture { select(cell.diffLine, cell.side) }
                .accessibilityLabel("\(cell.side.rawValue), \(cell.kind.rawValue), line \(cell.lineNumber), \(cell.content)")
            } else {
                Color.secondary.opacity(0.055).accessibilityLabel("Alignment gap")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .font(.system(size: 12, design: .monospaced)).lineLimit(1)
    }
}

private struct FullFileSourceView: View {
    let row: FullFileSourceRow
    let highlightedContent: AttributedString
    let annotationCount: Int
    let isSelected: Bool
    let select: () -> Void
    let openAnnotations: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Text(String(row.lineNumber)).foregroundStyle(.secondary).frame(width: 54, alignment: .trailing).padding(.trailing, 6)
            Text(row.kind == .added ? "+" : row.kind == .removed ? "−" : " ").frame(width: 24)
            Group {
                if annotationCount > 0 {
                    Button(action: openAnnotations) { Image(systemName: "text.bubble.fill").foregroundStyle(.blue) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View \(annotationCount) comment\(annotationCount == 1 ? "" : "s")")
                } else { Color.clear }
            }.frame(width: 24)
            Text(highlightedContent).textSelection(.enabled).padding(.horizontal, 6)
            Spacer(minLength: 20)
        }
        .frame(minHeight: 20).font(.system(size: 12, design: .monospaced)).lineLimit(1)
        .background(isSelected ? Color.accentColor.opacity(0.24) : row.kind == .added ? Color.green.opacity(0.14) : row.kind == .removed ? Color.red.opacity(0.14) : .clear)
        .contentShape(Rectangle()).onTapGesture { select() }
        .accessibilityHint("Selects this line; Shift-click extends the selection")
    }
}

private struct FullFileDeletionView: View {
    let model: ApplicationModel
    let marker: FullFileDeletionMarker
    let oldHighlights: [Int: AttributedString]
    let annotations: [ReviewAnnotation]
    let selection: ReviewLineSelection?
    let inlineCommentFocus: ReviewCommentFocus?
    let fileID: String
    let repositoryID: UUID
    let filePath: String
    let select: (DiffLine) -> Void
    let toggleComments: (Int) -> Void
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.bold()).frame(width: 14)
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    Text("\(marker.removedLineCount) deleted line\(marker.removedLineCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(oldLineSummary).foregroundStyle(.secondary)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.red.opacity(0.07))
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            if expanded {
                ForEach(Array(marker.removedLines.enumerated()), id: \.offset) { index, content in
                    let lineNumber = marker.oldStartLine + index
                    let comments = annotations.filter { $0.side == .old && $0.startLine...$0.endLine ~= lineNumber }
                    let row = FullFileSourceRow(
                        id: "\(marker.id):old:\(lineNumber)",
                        side: .old,
                        lineNumber: lineNumber,
                        kind: .removed,
                        content: content
                    )
                    VStack(spacing: 0) {
                        FullFileSourceView(
                            row: row,
                            highlightedContent: oldHighlights[lineNumber] ?? AttributedString(content),
                            annotationCount: comments.count,
                            isSelected: selection?.contains(fileID: fileID, side: .old, line: lineNumber) == true,
                            select: { select(row.diffLine) },
                            openAnnotations: { toggleComments(lineNumber) }
                        )
                        if inlineCommentFocus == ReviewCommentFocus(repositoryID: repositoryID, filePath: filePath, side: .old, line: lineNumber), !comments.isEmpty {
                            InlineReviewThread(model: model, annotations: comments)
                        }
                    }
                }
            }
        }
        .onAppear { revealFocusedDeletionIfNeeded() }
        .onChange(of: inlineCommentFocus) { _, _ in revealFocusedDeletionIfNeeded() }
    }

    private var oldLineSummary: String {
        let end = marker.oldStartLine + marker.removedLineCount - 1
        return end == marker.oldStartLine ? "old line \(end)" : "old lines \(marker.oldStartLine)–\(end)"
    }

    private func revealFocusedDeletionIfNeeded() {
        guard let inlineCommentFocus,
              inlineCommentFocus.repositoryID == repositoryID,
              inlineCommentFocus.filePath == filePath,
              inlineCommentFocus.side == .old,
              marker.oldStartLine..<(marker.oldStartLine + marker.removedLineCount) ~= inlineCommentFocus.line else { return }
        expanded = true
    }
}

private struct AnnotationComposerState: Identifiable {
    let id = UUID()
    let file: WorkspaceFileDiff
    let side: DiffSide
    let startLine: Int
    let endLine: Int
    let selectedCode: String
    let context: String
}

private struct AnnotationComposer: View {
    enum Destination: String, CaseIterable { case comment = "Comment", codex = "Ask Codex", copilot = "Ask Copilot", terminal = "Send to Terminal" }
    @Environment(\.dismiss) private var dismiss
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    let state: AnnotationComposerState
    let onSaved: (ReviewAnnotation) -> Void
    @State private var destination: Destination = .comment
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Annotate \(state.file.diff.path)").font(.headline)
            Text(lineSummary).font(.caption).foregroundStyle(.secondary)
            Picker("Destination", selection: $destination) { ForEach(Destination.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            ScrollView([.vertical, .horizontal]) {
                Text(state.selectedCode)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10).frame(maxWidth: .infinity, maxHeight: 180, alignment: .leading).background(.quaternary)
            TextEditor(text: $text).frame(minHeight: 120).overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
            Text("Terminal handoff inserts this text through Ghostty and never presses Enter.").font(.caption).foregroundStyle(.secondary).opacity(destination == .terminal ? 1 : 0)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button(destination == .comment ? "Save" : "Submit") { submit() }.keyboardShortcut(.defaultAction).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(20).frame(width: 620)
    }

    private var lineSummary: String {
        let side = state.side == .old ? "old" : "new"
        return state.startLine == state.endLine
            ? "\(side.capitalized) line \(state.startLine)"
            : "\(side.capitalized) lines \(state.startLine)–\(state.endLine)"
    }
    private func submit() {
        Task {
            let kind: AnnotationKind = destination == .comment ? .comment : .question
            guard let annotation = await model.saveAnnotation(workspaceID: workspace.id, repositoryID: state.file.repositoryID, file: state.file, kind: kind, side: state.side, startLine: state.startLine, endLine: state.endLine, selectedCode: state.selectedCode, context: state.context, text: text) else { return }
            switch destination {
            case .comment: break
            case .codex: await model.askAssistant(annotation: annotation, provider: .codex)
            case .copilot: await model.askAssistant(annotation: annotation, provider: .copilot)
            case .terminal: await model.sendAnnotationToTerminal(annotation)
            }
            onSaved(annotation)
            dismiss()
        }
    }
}
