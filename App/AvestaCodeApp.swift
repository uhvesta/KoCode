import AvestaCore
import AvestaNotifications
import AvestaUI
import SwiftUI

@main
struct AvestaCodeApp: App {
    @State private var appState = AppState()
    @State private var notificationService = NotificationService()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                .environment(notificationService)
                .task {
                    await notificationService.requestPermission()
                }
        }
        .commands {
            CommandMenu("Board") {
                Button("Toggle Board") {
                    appState.isBoardVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Paste Most Recent Board Item") {
                    appState.pasteMostRecentBoardItemToActiveTerminal()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}
