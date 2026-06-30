import AvestaCore
import SwiftUI

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspace.tabs, id: \.id) { tab in
                TabBarItem(
                    tab: tab,
                    isActive: workspace.activeTabID == tab.id,
                    badgeCount: appState.notificationBadges[tab.id, default: 0],
                    select: {
                        appState.selectTab(at: workspace.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0)
                    },
                    close: { appState.closeTab(id: tab.id) }
                )
            }

            NewTabMenu(workspace: workspace)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(height: 38)
        .background(.bar)
    }
}
