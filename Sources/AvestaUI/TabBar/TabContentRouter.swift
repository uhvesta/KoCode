import AvestaCore
import AvestaTerminal
import SwiftUI

struct TabContentRouter: View {
    let tab: any WorkspaceTab

    var body: some View {
        switch tab.kind {
        case .terminal:
            if let terminal = tab as? TerminalTabModel {
                TerminalSurfaceView(workingDirectory: terminal.workingDirectory, tabModel: terminal)
                    .overlay(alignment: .topLeading) {
                        TerminalPlaceholderOverlay(tab: terminal)
                    }
            }
        case .codeReview:
            if let codeReview = tab as? CodeReviewTabModel {
                CodeReviewView(model: codeReview)
            }
        }
    }
}

private struct TerminalPlaceholderOverlay: View {
    let tab: TerminalTabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal")
                .font(.headline)
            Text(tab.workingDirectory.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let pendingPaste = tab.pendingPaste {
                Text(pendingPaste)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
    }
}
