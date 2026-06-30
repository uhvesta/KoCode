import AvestaCore
import SwiftUI

public struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewWorkspace = false
    @State private var showingAddRepository = false
    private let onTerminalOutput: (UUID, String) -> Void

    public init(onTerminalOutput: @escaping (UUID, String) -> Void = { _, _ in }) {
        self.onTerminalOutput = onTerminalOutput
    }

    public var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            WorkspaceSidebar(
                showingNewWorkspace: $showingNewWorkspace,
                showingAddRepository: $showingAddRepository
            )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    if let workspace = appState.activeWorkspace {
                        TabBarView(workspace: workspace)
                        Divider()
                        if let tab = workspace.activeTab {
                            TabContentRouter(tab: tab, onTerminalOutput: onTerminalOutput)
                        } else {
                            ContentUnavailableView("No Tab", systemImage: "rectangle.on.rectangle.slash")
                        }
                    } else {
                        ContentUnavailableView("No Workspace", systemImage: "folder.badge.plus")
                    }
                }

                if appState.isBoardVisible, let workspace = appState.activeWorkspace {
                    BoardPanel(board: workspace.board)
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                        .shadow(radius: 10)
                }
            }
            .overlay(alignment: .top) {
                NotificationBanner()
                    .padding(.top, 12)
            }
        }
        .sheet(isPresented: $showingNewWorkspace) {
            NewWorkspaceSheet()
        }
        .sheet(isPresented: $showingAddRepository) {
            AddRepositorySheet()
        }
    }
}
