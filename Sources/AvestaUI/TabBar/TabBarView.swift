import AvestaCore
import SwiftUI

struct TabBarView: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspace.tabs, id: \.id) { tab in
                TabBarItem(
                    tab: tab,
                    isActive: workspace.activeTabID == tab.id,
                    select: { workspace.activeTabID = tab.id },
                    close: { workspace.closeTab(id: tab.id) }
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
