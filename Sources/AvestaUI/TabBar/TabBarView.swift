import AvestaCore
import ComposableArchitecture
import SwiftUI

struct TabBarView: View {
    let store: StoreOf<AppFeature>
    let workspace: AppFeature.WorkspaceState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspace.tabs, id: \.id) { tab in
                TabBarItem(
                    tab: tab,
                    isActive: workspace.activeTabID == tab.id,
                    badgeCount: store.notificationBadges[tab.id, default: 0],
                    select: {
                        store.send(.selectTab(index: workspace.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0))
                    },
                    close: { store.send(.closeTab(tab.id)) }
                )
            }

            NewTabMenu(store: store)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(height: 38)
        .background(.bar)
    }
}
