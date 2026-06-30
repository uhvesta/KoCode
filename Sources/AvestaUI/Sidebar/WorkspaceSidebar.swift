import AvestaCore
import ComposableArchitecture
import SwiftUI

struct WorkspaceSidebar: View {
    let store: StoreOf<AppFeature>
    @Binding var showingNewWorkspace: Bool
    @Binding var showingAddRepository: Bool

    var body: some View {
        List(selection: Binding(
            get: { store.activeWorkspaceID },
            set: { store.send(.selectWorkspace($0)) }
        )) {
            Section("Workspaces") {
                ForEach(store.workspaces) { workspace in
                    WorkspaceRow(store: store, workspace: workspace)
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
                .disabled(store.activeWorkspace == nil)

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
