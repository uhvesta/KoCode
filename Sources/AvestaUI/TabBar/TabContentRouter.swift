import AvestaCore
import AvestaTerminal
import ComposableArchitecture
import SwiftUI

struct TabContentRouter: View {
    let store: StoreOf<AppFeature>
    let tab: AppFeature.TabState
    var onTerminalOutput: (UUID, String) -> Void = { _, _ in }

    var body: some View {
        switch tab {
        case .terminal(let terminal):
                TerminalSurfaceView(
                    workingDirectory: terminal.workingDirectory,
                    tabID: terminal.id,
                    pendingPaste: terminal.pendingPaste,
                    resume: terminal.resume,
                    onOutput: { output in
                        store.send(.terminalOutput(tabID: terminal.id, output: output))
                        onTerminalOutput(terminal.id, output)
                    },
                    onPasteConsumed: {
                        store.send(.terminalPasteConsumed(tabID: terminal.id))
                    }
                )
        case .codeReview(let codeReview):
            CodeReviewView(store: store, tab: codeReview)
        }
    }
}
