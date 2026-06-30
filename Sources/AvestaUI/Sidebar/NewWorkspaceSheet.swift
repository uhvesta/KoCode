import AvestaCore
import ComposableArchitecture
import SwiftUI

struct NewWorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workspace")
                .font(.title2.weight(.semibold))

            TextField("Name", text: Binding(
                get: { store.newWorkspaceForm.name },
                set: { store.send(.newWorkspace(.nameChanged($0))) }
            ))
                .textFieldStyle(.roundedBorder)

            TextField("Repository URL", text: Binding(
                get: { store.newWorkspaceForm.remoteURL },
                set: { store.send(.newWorkspace(.remoteURLChanged($0))) }
            ))
                .textFieldStyle(.roundedBorder)
                .disabled(store.newWorkspaceForm.selectedCachedRepoID != nil)

            if !store.cachedRepos.isEmpty {
                Picker("Existing local clone", selection: Binding(
                    get: { store.newWorkspaceForm.selectedCachedRepoID },
                    set: { store.send(.newWorkspace(.selectedCachedRepoChanged($0))) }
                )) {
                    Text("Clone from URL").tag(UUID?.none)
                    ForEach(store.cachedRepos) { repo in
                        Text("\(repo.name)  \(repo.remoteURL)").tag(UUID?.some(repo.id))
                    }
                }
            }

            TextField("Branch", text: Binding(
                get: { store.newWorkspaceForm.branch },
                set: { store.send(.newWorkspace(.branchChanged($0))) }
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
                    store.send(.newWorkspace(.cancelButtonTapped))
                    dismiss()
                }
                Button("Create") {
                    store.send(.newWorkspace(.createButtonTapped(id: UUID())))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!store.newWorkspaceForm.isValid || store.newWorkspaceForm.isCreating)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: store.newWorkspaceForm.isCreating) { _, isCreating in
            if !isCreating, store.lastErrorMessage == nil, store.newWorkspaceForm.name.isEmpty {
                dismiss()
            }
        }
    }
}
