import AvestaCore
import SwiftUI

struct WorkspaceSidebar: View {
    @Environment(AppState.self) private var appState
    @Binding var showingNewWorkspace: Bool
    @Binding var showingAddRepository: Bool

    var body: some View {
        @Bindable var appState = appState

        List(selection: Binding(
            get: { appState.activeWorkspaceID },
            set: { appState.selectWorkspace(id: $0) }
        )) {
            Section("Workspaces") {
                ForEach(appState.workspaces) { workspace in
                    WorkspaceRow(workspace: workspace)
                        .tag(workspace.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    showingAddRepository = true
                } label: {
                    Label("Add Repository", systemImage: "plus.rectangle.on.folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState.activeWorkspace == nil)

                Button {
                    showingNewWorkspace = true
                } label: {
                    Label("New Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
