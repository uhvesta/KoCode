import AvestaCore
import AvestaTerminal
import SwiftUI

struct TabContentRouter: View {
    @Environment(AppState.self) private var appState
    let tab: any WorkspaceTab
    var onTerminalOutput: (UUID, String) -> Void = { _, _ in }

    var body: some View {
        switch tab.kind {
        case .terminal:
            if let terminal = tab as? TerminalTabModel {
                TerminalSurfaceView(
                    workingDirectory: terminal.workingDirectory,
                    tabModel: terminal,
                    onOutput: { output in
                        onTerminalOutput(terminal.id, output)
                    }
                )
            } else {
                ContentUnavailableView("Unsupported Terminal Tab", systemImage: "terminal")
            }
        case .codeReview:
            if let codeReview = tab as? CodeReviewTabModel {
                CodeReviewView(model: codeReview)
            } else {
                ContentUnavailableView("Unsupported Code Review Tab", systemImage: "text.page")
            }
        }
    }
}
