import AppKit
import AvestaCore
import SwiftUI

struct WorkspaceSidebar: View {
    @Bindable var model: ApplicationModel
    @Binding var showingNewWorkspace: Bool
    @Binding var showingAddRepository: Bool
    @Binding var showingRepositoryBank: Bool

    var body: some View {
        List(selection: $model.activeWorkspaceID) {
            Section("Workspaces") {
                ForEach(model.workspaces) { workspace in
                    WorkspaceRow(model: model, workspace: workspace)
                        .tag(workspace.id)
                        .contextMenu { workspaceMenu(workspace) }
                }
                .onMove { source, destination in Task { await model.reorderWorkspaces(fromOffsets: source, toOffset: destination) } }
            }

            Section("Repository Bank") {
                if model.repositorySources.isEmpty {
                    Text("No shared repositories yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.repositorySources) { source in
                        Text(source.repositoryIdentity)
                            .lineLimit(1)
                            .help(source.displayRemoteURL)
                            .contextMenu { Button("Fetch Latest") { Task { await model.fetchRepositorySource(id: source.id) } } }
                    }
                }
            }
        }
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItemGroup {
                Button("New Workspace", systemImage: "plus") { showingNewWorkspace = true }
                Button("Add Repository") { showingRepositoryBank = true }
            }
        }
    }

    @ViewBuilder private func workspaceMenu(_ workspace: WorkspaceRecord) -> some View {
        Button("Add Repository to Workspace") { model.activeWorkspaceID = workspace.id; showingAddRepository = true }
        Button("Start New Workspace Session") { Task { await model.startNewActivitySession(workspaceID: workspace.id) } }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([workspace.path]) }
        Divider()
        Button("Delete", role: .destructive) { Task { await model.deleteWorkspace(id: workspace.id) } }
    }
}

private struct WorkspaceRow: View {
    let model: ApplicationModel
    let workspace: WorkspaceRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.attentionWorkspaceIDs.contains(workspace.id) ? "bell.badge.fill" : "folder.fill")
                .foregroundStyle(model.attentionWorkspaceIDs.contains(workspace.id) ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.name).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 5) {
                    Text("\(workspace.repositories.count) repos")
                    Text("•")
                    Text(workspace.branchSummary)
                    if model.dirtyCounts[workspace.id, default: 0] > 0 { Text("• \(model.dirtyCounts[workspace.id, default: 0]) changes").foregroundStyle(.orange) }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
