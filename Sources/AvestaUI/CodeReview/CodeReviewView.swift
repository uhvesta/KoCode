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
                ZStack(alignment: .topTrailing) {
                    HSplitView {
                        fileList(flow: flow)
                            .frame(minWidth: 220, idealWidth: 320, maxWidth: 520)
                        SideBySideDiffView(
                            session: flow.session,
                            navigation: flow.navigation,
                            previousChange: {
                                store.send(.codeReview(tabID: tab.id, .previousChangeButtonTapped))
                            },
                            nextChange: {
                                store.send(.codeReview(tabID: tab.id, .nextChangeButtonTapped))
                            }
                        ) { file, line in
                            guard let lineNumber = line.newLineNumber else { return }
                            store.send(.codeReview(
                                tabID: tab.id,
                                .selectLine(CodeReviewFlowFeature.PendingLine(fileID: file.id, lineNumber: lineNumber, content: line.content))
                            ))
                        }
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    if flow.selectedLine != nil {
                        CommentOverlay(text: Binding(
                            get: { flow.commentText },
                            set: { store.send(.codeReview(tabID: tab.id, .commentTextChanged($0))) }
                        )) {
                            store.send(.codeReview(tabID: tab.id, .saveCommentButtonTapped(id: UUID(), createdAt: Date())))
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
                    .accessibilityIdentifier("code-review-preview")

                    Button {
                        store.send(.codeReview(tabID: tab.id, .sendReviewToBoardButtonTapped(id: UUID(), now: Date())))
                    } label: {
                        Label("Send to Board", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("code-review-send-to-board")
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

    private var loadDiffView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Code Review")
                .font(.title2.weight(.semibold))

            Picker("Repository", selection: $selectedRepoID) {
                Text("Select a repository").tag(UUID?.none)
                ForEach(store.activeWorkspace?.repos ?? []) { repo in
                    Text(repo.repoName).tag(UUID?.some(repo.id))
                }
            }
            .frame(maxWidth: 420)

            TextField("Diff spec", text: $diffSpec)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)

            if let error = store.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                store.send(.codeReviewLoadDiff(tabID: tab.id, repoID: selectedRepoID, diffSpec: diffSpec))
            } label: {
                Label("Load Diff", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRepo == nil || diffSpec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileList(flow: CodeReviewFlowFeature.State) -> some View {
        List(selection: Binding(
            get: { flow.session.activeFileIndex },
            set: {
                guard let index = $0 else { return }
                store.send(.codeReview(tabID: tab.id, .activeFileChanged(index)))
            }
        )) {
            ForEach(Array(flow.session.files.enumerated()), id: \.element.id) { index, file in
                Label(file.path, systemImage: icon(for: file.status))
                    .tag(index)
                    .accessibilityIdentifier("code-review-file-\(index)")
            }
        }
        .accessibilityIdentifier("code-review-file-list")
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
        guard let selectedRepoID else { return store.activeWorkspace?.repos.first }
        return store.activeWorkspace?.repos.first { $0.id == selectedRepoID }
    }
}
