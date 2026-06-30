import AvestaCore
import SwiftUI

struct NewTabMenu: View {
    @Environment(AppState.self) private var appState
    let workspace: Workspace

    var body: some View {
        Menu {
            Button {
                appState.addTerminalTab()
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .keyboardShortcut("t", modifiers: .command)

            Button {
                appState.addCodeReviewTab()
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
