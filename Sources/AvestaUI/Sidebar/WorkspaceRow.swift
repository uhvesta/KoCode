import AvestaCore
import ComposableArchitecture
import SwiftUI

struct WorkspaceRow: View {
    let store: StoreOf<AppFeature>
    let workspace: AppFeature.WorkspaceState

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .lineLimit(1)
                Text(workspace.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "folder")
        }
        .contextMenu {
            Button(role: .destructive) {
                store.send(.deleteWorkspace(workspace.id))
            } label: {
                Label("Delete Workspace", systemImage: "trash")
            }

            Button {
                store.send(.closeWorkspace(workspace.id))
            } label: {
                Label("Close Workspace", systemImage: "xmark.circle")
            }
        }
    }
}
