import AvestaCore
import SwiftUI

struct BoardPanel: View {
    @Environment(AppState.self) private var appState
    let board: BoardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Board")
                .font(.headline)
                .padding()

            Divider()

            if board.items.isEmpty {
                ContentUnavailableView("No Board Items", systemImage: "clipboard")
            } else {
                List(board.items) { item in
                    BoardItemRow(item: item) {
                        appState.pasteBoardItemToActiveTerminal(item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(.regularMaterial)
    }
}
