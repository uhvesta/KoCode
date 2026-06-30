import AvestaCore
import SwiftUI

struct WorkspaceRow: View {
    @Environment(AppState.self) private var appState
    let workspace: Workspace

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
                Task {
                    await appState.deleteWorkspace(id: workspace.id)
                }
            } label: {
                Label("Delete Workspace", systemImage: "trash")
            }
        }
    }
}
