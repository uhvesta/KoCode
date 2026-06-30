import AvestaCore
import ComposableArchitecture
import SwiftUI

public struct SettingsView: View {
    let store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Paths") {
                TextField("Workspaces Root", text: Binding(
                    get: { store.settings.config.workspacesRoot.path },
                    set: { store.send(.settings(.workspacesRootChanged($0))) }
                ))
                TextField("Cache Root", text: Binding(
                    get: { store.settings.config.cacheRoot.path },
                    set: { store.send(.settings(.cacheRootChanged($0))) }
                ))
            }

            Section("Notification Patterns") {
                ForEach(store.settings.config.notificationPatterns.indices, id: \.self) { index in
                    TextField("Pattern", text: Binding(
                        get: { store.settings.config.notificationPatterns[index] },
                        set: { store.send(.settings(.notificationPatternChanged(index: index, value: $0))) }
                    ))
                        .font(.system(.body, design: .monospaced))
                }

                Button {
                    store.send(.settings(.addNotificationPatternButtonTapped))
                } label: {
                    Label("Add Pattern", systemImage: "plus")
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 360)
    }
}
