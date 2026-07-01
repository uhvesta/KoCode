import AvestaCore
import AvestaTerminal
import ComposableArchitecture
import Foundation
import SwiftUI

struct TabContentRouter: View {
    let store: StoreOf<AppFeature>
    let tab: AppFeature.TabState
    var onTerminalOutput: (UUID, String) -> Void = { _, _ in }

    var body: some View {
        switch tab {
        case .terminal(let terminal):
            if Self.isRunningUnderXCTest {
                TerminalSnapshotPlaceholder(terminal: terminal)
            } else {
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
            }
        case .codeReview(let codeReview):
            CodeReviewView(store: store, tab: codeReview)
        }
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct TerminalSnapshotPlaceholder: View {
    let terminal: AppFeature.TerminalTabState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "terminal")
                Text(terminal.workingDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                Text(terminal.outputBuffer.isEmpty ? "$ " : terminal.outputBuffer)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
