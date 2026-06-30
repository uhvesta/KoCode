import AvestaCore
import SwiftUI

struct NewWorkspaceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Workspace")
                .font(.title2.weight(.semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Create") {
                    appState.createWorkspace(name: sanitizedName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sanitizedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var sanitizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
