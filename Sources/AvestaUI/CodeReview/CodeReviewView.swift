import AvestaCore
import ComposableArchitecture
import SwiftUI

struct CodeReviewView: View {
    let store: StoreOf<AppFeature>
    let tab: AppFeature.CodeReviewTabState
    @State private var selectedRepoID: UUID?
    @State private var diffSpec = "main...HEAD"
    @State private var showingSummary = false

    var body: some View {
        Group {
            if let flow = tab.flow {
                VStack(spacing: 0) {
                    reviewHeader(flow: flow)
                    Divider()

                    HStack(spacing: 0) {
                        fileList(flow: flow)
                            .frame(width: 240)
                        Divider()

                        reviewContent(flow: flow)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .toolbar {
                    Button {
                        showingSummary.toggle()
                    } label: {
                        Label("Preview", systemImage: "doc.plaintext")
                    }
                    .accessibilityIdentifier("code-review-preview")
                }
                .sheet(isPresented: $showingSummary) {
                    ReviewSummaryView(markdown: flow.session.markdown())
                        .frame(minWidth: 720, minHeight: 520)
                }
            } else {
                loadDiffView
            }
        }
    }

    private func reviewHeader(flow: CodeReviewFlowFeature.State) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Review Scope", selection: Binding(
                    get: { flow.session.scope },
                    set: { store.send(.codeReviewSelectScope(tabID: tab.id, $0)) }
                )) {
                    Text("Git changes \(flow.session.files.count)").tag(CodeReviewScope.gitChanges)
                    Text("Last turn changes \(flow.session.lastTurnFiles.count)").tag(CodeReviewScope.lastTurnChanges)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                .accessibilityIdentifier("code-review-scope-picker")

                Picker("Diff Mode", selection: Binding(
                    get: { flow.session.diffMode },
                    set: { store.send(.codeReview(tabID: tab.id, .diffModeSelected($0))) }
                )) {
                    ForEach(CodeReviewDiffMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                .accessibilityIdentifier("code-review-diff-mode-picker")

                Button {
                    store.send(.codeReviewLoadGitChanges(tabID: tab.id, repoID: repoID(matching: flow.session.repoPath)))
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Refresh")
                .help("Reload Git changes")

                Button {
                    store.send(.codeReviewMarkReviewed(tabID: tab.id, now: Date()))
                } label: {
                    Label("Mark reviewed", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("code-review-mark-reviewed")

                Button {
                    store.send(.codeReview(tabID: tab.id, .sendReviewToBoardButtonTapped(id: UUID(), now: Date())))
                } label: {
                    Label("Send all", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(flow.session.comments.isEmpty)
                .help("Send all review comments to the Board as one item")
                .accessibilityIdentifier("code-review-send-all-comments")

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                if let checkpoint = flow.session.checkpoint {
                    Text("Last reviewed \(formatted(checkpoint.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No review checkpoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func reviewContent(flow: CodeReviewFlowFeature.State) -> some View {
        let error = flow.session.scope == .gitChanges ? flow.session.gitChangesError : flow.session.lastTurnError
        if let error {
            errorState(flow: flow, message: error)
        } else if flow.session.activeFiles.isEmpty {
            emptyState(flow: flow)
        } else {
            SideBySideDiffView(
                session: flow.session,
                navigation: flow.navigation,
                previousChange: {
                    store.send(.codeReview(tabID: tab.id, .previousChangeButtonTapped))
                },
                nextChange: {
                    store.send(.codeReview(tabID: tab.id, .nextChangeButtonTapped))
                },
                selectedLine: flow.selectedLine,
                commentText: flow.commentText,
                onSelectLine: { file, line in
                    guard let lineNumber = line.newLineNumber else { return }
                    store.send(.codeReview(
                        tabID: tab.id,
                        .selectLine(CodeReviewFlowFeature.PendingLine(
                            fileID: file.id,
                            lineNumber: lineNumber,
                            content: line.content
                        ))
                    ))
                },
                onCommentTextChanged: {
                    store.send(.codeReview(tabID: tab.id, .commentTextChanged($0)))
                },
                onSaveComment: {
                    store.send(.codeReview(tabID: tab.id, .saveCommentButtonTapped(id: UUID(), createdAt: Date())))
                },
                onCancelComment: {
                    store.send(.codeReview(tabID: tab.id, .cancelCommentButtonTapped))
                },
                onDeleteComment: {
                    store.send(.codeReview(tabID: tab.id, .deleteCommentButtonTapped($0)))
                }
            )
        }
    }

    private var loadDiffView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review")
                .font(.title2.weight(.semibold))

            Picker("Repository", selection: $selectedRepoID) {
                Text("Select a repository").tag(UUID?.none)
                ForEach(store.activeWorkspace?.repos ?? []) { repo in
                    Text(repo.repoName).tag(UUID?.some(repo.id))
                }
            }
            .frame(maxWidth: 420)

            if let error = store.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 10) {
                Button {
                    store.send(.codeReviewLoadGitChanges(tabID: tab.id, repoID: selectedRepo?.id))
                } label: {
                    Label("Load Git Changes", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedRepo == nil)

                TextField("Optional diff spec", text: $diffSpec)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Button {
                    store.send(.codeReviewLoadDiff(tabID: tab.id, repoID: selectedRepo?.id, diffSpec: diffSpec))
                } label: {
                    Label("Load Spec", systemImage: "arrow.left.arrow.right")
                }
                .disabled(selectedRepo == nil || diffSpec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileList(flow: CodeReviewFlowFeature.State) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(flow.session.activeFiles.enumerated()), id: \.element.id) { index, file in
                    Button {
                        store.send(.codeReview(tabID: tab.id, .activeFileChanged(index)))
                    } label: {
                        FileRow(
                            file: file,
                            scope: flow.session.scope,
                            commentCount: flow.session.comments.filter { $0.fileID == file.id }.count
                        )
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                        .background(index == flow.session.activeFileIndex ? Color(red: 0.13, green: 0.11, blue: 0.09) : Color.clear)
                        .overlay(alignment: .leading) {
                            if index == flow.session.activeFileIndex {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("code-review-file-\(index)")

                    Divider()
                        .padding(.leading, 10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .accessibilityIdentifier("code-review-file-list")
    }

    private func emptyState(flow: CodeReviewFlowFeature.State) -> some View {
        let title: String
        let message: String
        switch flow.session.scope {
        case .gitChanges:
            title = "No Git changes"
            message = "Working tree is clean."
        case .lastTurnChanges:
            if flow.session.checkpoint == nil {
                title = "No review checkpoint"
                message = "Mark current changes as reviewed to start tracking last-turn changes."
            } else {
                title = "No changes since last review"
                message = "Continue working or reset the review checkpoint."
            }
        }

        return ContentUnavailableView(title, systemImage: "checkmark.circle", description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(flow: CodeReviewFlowFeature.State, message: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                flow.session.scope == .gitChanges ? "Could not load Git changes" : "Could not load Last turn changes",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )

            HStack {
                Button("Retry") {
                    if flow.session.scope == .gitChanges {
                        store.send(.codeReviewLoadGitChanges(tabID: tab.id, repoID: repoID(matching: flow.session.repoPath)))
                    } else {
                        store.send(.codeReviewSelectScope(tabID: tab.id, .lastTurnChanges))
                    }
                }
                Button("Show Git changes") {
                    store.send(.codeReviewSelectScope(tabID: tab.id, .gitChanges))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repoID(matching path: URL) -> UUID? {
        store.activeWorkspace?.repos.first { $0.worktreePath == path }?.id ?? selectedRepo?.id
    }

    private var selectedRepo: WorktreeRef? {
        guard let selectedRepoID else { return store.activeWorkspace?.repos.first }
        return store.activeWorkspace?.repos.first { $0.id == selectedRepoID }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FileRow: View {
    let file: FileDiff
    let scope: CodeReviewScope
    let commentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(file.path)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(summary)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch file.status {
        case .added: return "plus.circle"
        case .modified: return "doc.text"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        }
    }

    private var summary: String {
        if file.status == .added {
            return "Added +\(file.addedLineCount)"
        }
        return "+\(file.addedLineCount)  -\(file.removedLineCount)"
    }

    private var metadata: String {
        if scope == .lastTurnChanges {
            return file.status == .added ? "Added since last review" : "Changed since last review"
        }
        if commentCount == 1 {
            return "1 comment"
        }
        if commentCount > 1 {
            return "\(commentCount) comments"
        }
        return ""
    }
}
