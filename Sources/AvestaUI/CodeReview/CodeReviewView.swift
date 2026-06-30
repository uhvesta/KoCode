import AvestaCore
import SwiftUI

struct CodeReviewView: View {
    let model: CodeReviewTabModel
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let session = model.session {
                HSplitView {
                    fileList(session: session)
                        .frame(minWidth: 220, idealWidth: 260)
                    SideBySideDiffView(session: session)
                        .frame(minWidth: 560)
                }
                .toolbar {
                    Button {
                        appState.activeWorkspace?.board.send(
                            session.toMarkdown(),
                            source: "Code Review: \(session.diffSpec)"
                        )
                    } label: {
                        Label("Send to Board", systemImage: "square.and.arrow.up")
                    }
                }
            } else {
                ContentUnavailableView("No Diff Loaded", systemImage: "text.page", description: Text("Create a CodeReviewSession from GitService.diff to review changes."))
            }
        }
    }

    private func fileList(session: CodeReviewSession) -> some View {
        List(selection: Binding(
            get: { session.activeFileIndex },
            set: { session.activeFileIndex = $0 }
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
}
