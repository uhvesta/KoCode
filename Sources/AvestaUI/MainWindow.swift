import AvestaCore
import ComposableArchitecture
import SwiftUI

public struct MainWindow: View {
    @State private var showingNewWorkspace = false
    @State private var showingAddRepository = false
    let store: StoreOf<AppFeature>
    private let onTerminalOutput: (UUID, String) -> Void

    public init(store: StoreOf<AppFeature>, onTerminalOutput: @escaping (UUID, String) -> Void = { _, _ in }) {
        self.store = store
        self.onTerminalOutput = onTerminalOutput
    }

    public var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(
                store: store,
                showingNewWorkspace: $showingNewWorkspace,
                showingAddRepository: $showingAddRepository
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    if let workspace = store.activeWorkspace {
                        TabBarView(store: store, workspace: workspace)
                        Divider()
                        if let tab = workspace.activeTab {
                            TabContentRouter(store: store, tab: tab, onTerminalOutput: onTerminalOutput)
                        } else {
                            ContentUnavailableView("No Tab", systemImage: "rectangle.on.rectangle.slash")
                        }
                    } else {
                        ContentUnavailableView("No Workspace", systemImage: "folder.badge.plus")
                    }
                }

                if store.isBoardVisible, let workspace = store.activeWorkspace {
                    BoardPanel(store: store, items: workspace.boardItems)
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                        .shadow(radius: 10)
                }
            }
            .overlay(alignment: .top) {
                NotificationBanner(store: store)
                    .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingNewWorkspace) {
            NewWorkspaceSheet(store: store)
        }
        .sheet(isPresented: $showingAddRepository) {
            AddRepositorySheet(store: store)
        }
    }
}
