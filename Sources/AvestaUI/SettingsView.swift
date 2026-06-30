import AvestaCore
import SwiftUI

public struct SettingsView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var appState = appState

        Form {
            Section("Paths") {
                TextField("Workspaces Root", text: Binding(
                    get: { appState.config.workspacesRoot.path },
                    set: { appState.config.workspacesRoot = URL(fileURLWithPath: $0, isDirectory: true) }
                ))
                TextField("Cache Root", text: Binding(
                    get: { appState.config.cacheRoot.path },
                    set: { appState.config.cacheRoot = URL(fileURLWithPath: $0, isDirectory: true) }
                ))
            }

            Section("Notification Patterns") {
                ForEach(appState.config.notificationPatterns.indices, id: \.self) { index in
                    TextField("Pattern", text: $appState.config.notificationPatterns[index])
                        .font(.system(.body, design: .monospaced))
                }

                Button {
                    appState.config.notificationPatterns.append("")
                } label: {
                    Label("Add Pattern", systemImage: "plus")
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 360)
    }
}
