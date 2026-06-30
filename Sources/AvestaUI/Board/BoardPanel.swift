import AvestaCore
import SwiftUI

struct BoardPanel: View {
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
                    BoardItemRow(item: item)
                }
                .listStyle(.plain)
            }
        }
        .background(.regularMaterial)
    }
}
