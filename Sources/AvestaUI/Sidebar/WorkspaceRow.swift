import AvestaCore
import SwiftUI

struct WorkspaceRow: View {
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
    }
}
