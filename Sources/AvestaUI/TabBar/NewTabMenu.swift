import AvestaCore
import SwiftUI

struct NewTabMenu: View {
    let workspace: Workspace

    var body: some View {
        Menu {
            Button {
                workspace.addTerminalTab()
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .keyboardShortcut("t", modifiers: .command)

            Button {
                workspace.addCodeReviewTab()
            } label: {
                Label("Code Review", systemImage: "text.page")
            }
        } label: {
            Image(systemName: "plus")
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .help("New Tab")
    }
}
