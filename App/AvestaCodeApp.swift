import AvestaCore
import AvestaNotifications
import AvestaUI
import SwiftUI

@main
struct AvestaCodeApp: App {
    @State private var appState = AppState()
    @State private var notificationService = NotificationService()
    @State private var outputMonitors: [UUID: OutputMonitor] = [:]
    private let agentEventClassifier = TerminalAgentEventClassifier()

    var body: some Scene {
        WindowGroup {
            MainWindow { tabID, output in
                if let event = agentEventClassifier.event(from: output) {
                    appState.incrementBadge(for: tabID)
                    appState.notifyInApp(title: event.title, body: event.body, tabID: tabID)
                    notificationService.notify(title: event.title, body: event.body, tabID: tabID)
                    return
                }

                let monitor = outputMonitors[tabID] ?? OutputMonitor(patterns: appState.config.notificationPatterns)
                outputMonitors[tabID] = monitor
                for match in monitor.ingest(output) {
                    appState.incrementBadge(for: tabID)
                    appState.notifyInApp(title: "Terminal Needs Attention", body: match.line, tabID: tabID)
                    notificationService.notify(title: "Terminal Needs Attention", body: match.line, tabID: tabID)
                }
            }
                .environment(appState)
                .task {
                    await notificationService.requestPermission()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Terminal") {
                    appState.addTerminalTab()
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Tabs") {
                Button("Close Tab") {
                    Task {
                        await appState.closeActiveTabOrCloseEmptyWorkspace()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                ForEach(1..<10) { index in
                    Button("Select Tab \(index)") {
                        appState.selectTab(at: index - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }

            CommandMenu("Board") {
                Button("Toggle Board") {
                    appState.isBoardVisible.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Send Terminal Output to Board") {
                    appState.sendActiveTerminalOutputToBoard()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Paste Most Recent Board Item") {
                    appState.pasteMostRecentBoardItemToActiveTerminal()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
