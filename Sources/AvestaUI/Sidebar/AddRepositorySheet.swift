import AvestaCore
import ComposableArchitecture
import SwiftUI

struct AddRepositorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Repository")
                .font(.title2.weight(.semibold))

            if let workspace = store.activeWorkspace {
                Text("Adds a worktree to \(workspace.name). Paste a Git URL, or reuse an existing local clone if one is listed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Repository URL", text: Binding(
                get: { store.addRepositoryForm.remoteURL },
                set: { store.send(.addRepository(.remoteURLChanged($0))) }
            ))
                .textFieldStyle(.roundedBorder)
                .disabled(store.addRepositoryForm.selectedCachedRepoID != nil)

            if !store.cachedRepos.isEmpty {
                Picker("Existing local clone", selection: Binding(
                    get: { store.addRepositoryForm.selectedCachedRepoID },
                    set: { store.send(.addRepository(.selectedCachedRepoChanged($0))) }
                )) {
                    Text("Clone from URL").tag(UUID?.none)
                    ForEach(store.cachedRepos) { repo in
                        Text("\(repo.name)  \(repo.remoteURL)").tag(UUID?.some(repo.id))
                    }
                }

                if store.addRepositoryForm.selectedCachedRepoID != nil {
                    Text("This skips cloning and creates another worktree from the existing bare clone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Branch", text: Binding(
                get: { store.addRepositoryForm.branch },
                set: { store.send(.addRepository(.branchChanged($0))) }
            ))
                .textFieldStyle(.roundedBorder)

            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    store.send(.addRepository(.cancelButtonTapped))
                    dismiss()
                }

                Button("Add") {
                    store.send(.addRepository(.addButtonTapped))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAddDisabled)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: store.addRepositoryForm.isAdding) { _, isAdding in
            if !isAdding, store.lastErrorMessage == nil, store.addRepositoryForm.remoteURL.isEmpty, store.addRepositoryForm.selectedCachedRepoID == nil {
                dismiss()
            }
        }
    }

    private var isAddDisabled: Bool {
        store.addRepositoryForm.isAdding || store.activeWorkspace == nil || !store.addRepositoryForm.isValid
    }
}
