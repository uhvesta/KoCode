import AvestaCore
import AvestaNotifications
import SwiftUI

public struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(NotificationService.self) private var notificationService
    @State private var showingNewWorkspace = false

    public init() {}

    public var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            WorkspaceSidebar(showingNewWorkspace: $showingNewWorkspace)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    if let workspace = appState.activeWorkspace {
                        TabBarView(workspace: workspace)
                        Divider()
                        if let tab = workspace.activeTab {
                            TabContentRouter(tab: tab)
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
        .onAppear {
            if appState.workspaces.isEmpty {
                appState.createWorkspace(name: "Default")
            }
        }
    }
}
