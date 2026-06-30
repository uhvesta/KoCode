import AvestaCore
import SwiftUI

struct AddRepositorySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCachedRepoID: UUID?
    @State private var remoteURL = ""
    @State private var branch = "main"
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Repository")
                .font(.title2.weight(.semibold))

            if let workspace = appState.activeWorkspace {
                Text("Adds a worktree to \(workspace.name). Paste a Git URL, or reuse an existing local clone if one is listed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Repository URL", text: $remoteURL)
                .textFieldStyle(.roundedBorder)
                .disabled(selectedCachedRepoID != nil)

            if !appState.cachedRepos.isEmpty {
                Picker("Existing local clone", selection: $selectedCachedRepoID) {
                    Text("Clone from URL").tag(UUID?.none)
                    ForEach(appState.cachedRepos) { repo in
                        Text("\(repo.name)  \(repo.remoteURL)").tag(UUID?.some(repo.id))
                    }
                }

                if selectedCachedRepoID != nil {
                    Text("This skips cloning and creates another worktree from the existing bare clone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Branch", text: $branch)
                .textFieldStyle(.roundedBorder)

            if let error = appState.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }

                Button("Add") {
                    addRepository()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAddDisabled)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var isAddDisabled: Bool {
        isAdding || appState.activeWorkspace == nil || (selectedCachedRepo == nil && remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var sanitizedBranch: String {
        let value = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "main" : value
    }

    private var selectedCachedRepo: CachedRepo? {
        guard let selectedCachedRepoID else { return nil }
        return appState.cachedRepos.first { $0.id == selectedCachedRepoID }
    }

    private func addRepository() {
        guard let workspaceID = appState.activeWorkspaceID ?? appState.activeWorkspace?.id else { return }
        isAdding = true
        Task {
            await appState.addRepository(
                to: workspaceID,
                cachedRepo: selectedCachedRepo,
                remoteURL: remoteURL,
                branch: sanitizedBranch
            )
            isAdding = false
            if appState.lastErrorMessage == nil {
                dismiss()
            }
        }
    }
}
