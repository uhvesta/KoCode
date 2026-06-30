import AvestaCore
import SwiftUI

struct WorkspaceSidebar: View {
    @Environment(AppState.self) private var appState
    @Binding var showingNewWorkspace: Bool

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.activeWorkspaceID) {
            Section("Workspaces") {
                ForEach(appState.workspaces) { workspace in
                    WorkspaceRow(workspace: workspace)
                        .tag(workspace.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showingNewWorkspace = true
            } label: {
                Label("New Workspace", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
