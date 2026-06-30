import AvestaCore
import ComposableArchitecture
import SwiftUI

struct BoardPanel: View {
    let store: StoreOf<AppFeature>
    let items: [BoardItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Board")
                .font(.headline)
                .padding()

            Divider()

            if items.isEmpty {
                ContentUnavailableView("No Board Items", systemImage: "clipboard")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            BoardItemRow(item: item) {
                                store.send(.pasteBoardItemToActiveTerminal(item.id))
                            }
                            Divider()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(.regularMaterial)
    }
}
