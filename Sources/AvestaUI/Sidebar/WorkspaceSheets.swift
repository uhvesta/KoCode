import AvestaCore
import SwiftUI

struct NewWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ApplicationModel
    @State private var name = ""
    @State private var repositoryRows: [RepositoryDraft] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workspace").font(.title2.bold())
            TextField("Name", text: $name)
            LabeledContent("Workspace folder", value: model.workspacePath(forName: name).path)
            Text("Select repositories from the global repository bank. Each selection creates a worktree inside this workspace.")
                .font(.caption)
                .foregroundStyle(.secondary)
            RepositoryDraftList(rows: $repositoryRows, sources: model.repositorySources)
            HStack { Button("Add Repository from Bank") { repositoryRows.append(RepositoryDraft()) }.disabled(model.repositorySources.isEmpty); Spacer(); Button("Cancel") { dismiss() }; Button("Create") { create() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repositoryRows.contains { $0.cachedSourceID == nil }) }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20).frame(width: 620, height: 440)
    }

    private func create() {
        Task { await model.createWorkspace(name: name, repositories: repositoryRows); dismiss() }
    }
}

struct RepositoryRowsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    @State private var rows = [RepositoryDraft()]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Repositories from Bank to \(workspace.name)").font(.title2.bold())
            RepositoryDraftList(rows: $rows, sources: model.repositorySources)
            ForEach(rows) { row in
                if let operation = model.repositoryOperations[row.id] {
                    HStack { ProgressView(value: operation.progress); Text(operation.message ?? operation.phase.rawValue).font(.caption) }
                }
            }
            HStack { Button("Add Row") { rows.append(RepositoryDraft()) }.disabled(model.repositorySources.isEmpty); Spacer(); Button("Cancel") { dismiss() }; Button("Add") { add() }.keyboardShortcut(.defaultAction).disabled(rows.isEmpty || rows.contains { $0.cachedSourceID == nil }) }
        }
        .padding(20).frame(width: 680, height: 440)
    }

    private func add() {
        Task { for row in rows where row.cachedSourceID != nil { await model.addRepository(row, to: workspace.id) }; if rows.allSatisfy({ model.repositoryOperations[$0.id]?.phase == .complete }) { dismiss() } }
    }
}

struct RepositoryBankSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ApplicationModel
    @State private var remoteURL = ""
    @State private var baseBranch = "origin/main"
    @State private var isAdding = false
    @State private var sourceToDelete: RepositorySourceRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Repository Bank").font(.title2.bold())
            Text("Add a remote once. AvestaCode stores one shared clone, then creates workspace-specific worktrees from it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("https://github.com/owner/repository or git@github.com:owner/repository.git", text: $remoteURL)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
            }
            TextField("Default base branch", text: $baseBranch)
                .help("New workspace worktrees will branch from this ref unless overridden later.")
            if isAdding { ProgressView("Cloning or fetching shared repository…") }
            List {
                ForEach(model.repositorySources) { source in
                    let inUse = model.workspaces.contains { workspace in workspace.repositories.contains { $0.sourceID == source.id } }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(source.repositoryIdentity)
                        TextField("Base branch", text: Binding(
                            get: { source.defaultBaseBranch },
                            set: { value in Task { await model.setRepositoryBaseBranch(sourceID: source.id, branch: value) } }
                        ))
                        .font(.caption)
                        Text(source.cachePath.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contextMenu {
                        Button("Fetch Latest") { Task { await model.fetchRepositorySource(id: source.id) } }
                        Button("Delete Repository", role: .destructive) { sourceToDelete = source }
                            .disabled(inUse)
                    }
                }
                .onMove { offsets, destination in
                    Task { await model.reorderRepositorySources(fromOffsets: offsets, toOffset: destination) }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() } }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 720, height: 500)
        .onAppear { baseBranch = model.defaultBaseBranch }
        .alert(item: $sourceToDelete) { source in
            Alert(
                title: Text("Delete \(source.repositoryIdentity)?"),
                message: Text("The shared clone will be removed. Repositories used by a workspace cannot be deleted."),
                primaryButton: .destructive(Text("Delete")) { Task { await model.deleteRepositorySource(id: source.id) } },
                secondaryButton: .cancel()
            )
        }
    }

    private func add() {
        let value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isAdding = true
        Task {
            await model.addRepositoryToBank(remoteURL: value, defaultBaseBranch: baseBranch)
            remoteURL = ""
            isAdding = false
        }
    }
}

private struct RepositoryDraftList: View {
    @Binding var rows: [RepositoryDraft]
    let sources: [RepositorySourceRecord]

    var body: some View {
        List {
            ForEach($rows) { $row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Repository", selection: $row.cachedSourceID) {
                            Text("Choose from bank").tag(UUID?.none)
                            ForEach(sources) { Text($0.repositoryIdentity).tag(UUID?.some($0.id)) }
                        }
                        Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                    Text("Branch: workspace name  •  Base: repository preference")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Base branch override (optional)", text: $row.baseBranch)
                        .font(.caption)
                }.padding(.vertical, 4)
            }.onMove { rows.move(fromOffsets: $0, toOffset: $1) }
        }
    }
}
