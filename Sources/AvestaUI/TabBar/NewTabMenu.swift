import AvestaCore
import ComposableArchitecture
import SwiftUI

struct NewTabMenu: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Menu {
            Button {
                store.send(.addTerminalTab(id: UUID()))
            } label: {
                Label("Terminal", systemImage: "terminal")
            }
            .keyboardShortcut("t", modifiers: .command)

            Button {
                store.send(.addCodeReviewTab(id: UUID()))
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
