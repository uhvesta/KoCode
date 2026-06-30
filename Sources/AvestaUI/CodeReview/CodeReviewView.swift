import AvestaCore
import SwiftUI

struct CodeReviewView: View {
    let model: CodeReviewTabModel
    @Environment(AppState.self) private var appState
    @State private var selectedRepoID: UUID?
    @State private var diffSpec = "main...HEAD"
    @State private var isLoading = false
    @State private var selectedLine: PendingComment?
    @State private var commentText = ""
    @State private var showingSummary = false

    var body: some View {
        Group {
            if let session = model.session {
                ZStack(alignment: .topTrailing) {
                    HSplitView {
                        fileList(session: session)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                        SideBySideDiffView(session: session) { file, line in
                            selectedLine = PendingComment(file: file, line: line)
                            commentText = existingCommentText(fileID: file.id, line: line.newLineNumber)
                        }
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    if selectedLine != nil {
                        CommentOverlay(text: $commentText) {
                            saveComment()
                        }
                        .padding()
                    }
                }
                .toolbar {
                    Button {
                        showingSummary.toggle()
                    } label: {
                        Label("Preview", systemImage: "doc.plaintext")
                    }

                    Button {
                        appState.activeWorkspace?.board.send(
                            session.toMarkdown(),
                            source: "Code Review: \(session.diffSpec)"
                        )
                        appState.persistSession()
                    } label: {
                        Label("Send to Board", systemImage: "square.and.arrow.up")
                    }
                }
                .sheet(isPresented: $showingSummary) {
                    ReviewSummaryView(session: session)
                        .frame(minWidth: 720, minHeight: 520)
                }
            } else {
                loadDiffView
            }
        }
    }

    private var loadDiffView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Code Review")
                .font(.title2.weight(.semibold))

            Picker("Repository", selection: $selectedRepoID) {
                Text("Select a repository").tag(UUID?.none)
                ForEach(appState.activeWorkspace?.repos ?? []) { repo in
                    Text(repo.repoName).tag(UUID?.some(repo.id))
                }
            }
            .frame(maxWidth: 420)

            TextField("Diff spec", text: $diffSpec)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)

            if let error = appState.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                loadDiff()
            } label: {
                Label(isLoading ? "Loading" : "Load Diff", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRepo == nil || isLoading || diffSpec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileList(session: CodeReviewSession) -> some View {
        List(selection: Binding(
            get: { session.activeFileIndex },
            set: {
                session.activeFileIndex = $0
                appState.persistSession()
            }
        )) {
            ForEach(Array(session.files.enumerated()), id: \.element.id) { index, file in
                Label(file.path, systemImage: icon(for: file.status))
                    .tag(index)
            }
        }
    }

    private func icon(for status: FileStatus) -> String {
        switch status {
        case .added: return "plus.circle"
        case .modified: return "circle"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        }
    }

    private var selectedRepo: WorktreeRef? {
        guard let selectedRepoID else { return appState.activeWorkspace?.repos.first }
        return appState.activeWorkspace?.repos.first { $0.id == selectedRepoID }
    }

    private func loadDiff() {
        guard let selectedRepo else { return }
        isLoading = true
        Task {
            do {
                let files = try await appState.gitService.diff(repoPath: selectedRepo.worktreePath, spec: diffSpec)
                appState.updateCodeReviewSession(
                    CodeReviewSession(diffSpec: diffSpec, repoPath: selectedRepo.worktreePath, files: files),
                    for: model.id
                )
                appState.lastErrorMessage = nil
            } catch {
                appState.lastErrorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func saveComment() {
        guard
            let pending = selectedLine,
            let lineNumber = pending.line.newLineNumber,
            !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            selectedLine = nil
            return
        }

        if let index = model.session?.comments.firstIndex(where: { $0.fileID == pending.file.id && $0.startLine == lineNumber }) {
            model.session?.comments[index].text = commentText
        } else {
            model.session?.addComment(
                fileID: pending.file.id,
                line: lineNumber,
                highlightedText: pending.line.content,
                text: commentText
            )
        }
        selectedLine = nil
        commentText = ""
        appState.persistSession()
    }

    private func existingCommentText(fileID: UUID, line: Int?) -> String {
        guard let line else { return "" }
        return model.session?.comments.first { $0.fileID == fileID && $0.startLine == line }?.text ?? ""
    }
}

private struct PendingComment {
    let file: FileDiff
    let line: DiffLine
}
