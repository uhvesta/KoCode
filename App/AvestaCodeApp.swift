import AvestaCore
import AvestaNotifications
import AvestaUI
import ComposableArchitecture
import SwiftUI

@main
struct AvestaCodeApp: App {
    private let store: StoreOf<AppFeature>
    @State private var notificationService = NotificationService()
    @State private var outputMonitors: [UUID: OutputMonitor] = [:]
    private let agentEventClassifier = TerminalAgentEventClassifier()

    init() {
        let config = AppConfig.default
        let sessionStore = AppSessionStore()
        self.store = Store(initialState: AppFeature.State.restored(config: config, sessionStore: sessionStore)) {
            AppFeature(config: config, sessionStore: sessionStore)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindow(store: store) { tabID, output in
                if let event = agentEventClassifier.event(from: output) {
                    store.send(.incrementBadge(tabID: tabID))
                    store.send(.notifyInApp(id: UUID(), title: event.title, body: event.body, tabID: tabID, createdAt: Date()))
                    notificationService.notify(title: event.title, body: event.body, tabID: tabID)
                    return
                }

                let monitor = outputMonitors[tabID] ?? OutputMonitor(patterns: store.settings.config.notificationPatterns)
                outputMonitors[tabID] = monitor
                for match in monitor.ingest(output) {
                    store.send(.incrementBadge(tabID: tabID))
                    store.send(.notifyInApp(id: UUID(), title: "Terminal Needs Attention", body: match.line, tabID: tabID, createdAt: Date()))
                    notificationService.notify(title: "Terminal Needs Attention", body: match.line, tabID: tabID)
                }
            }
                .task {
                    await notificationService.requestPermission()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Terminal") {
                    store.send(.addTerminalTab(id: UUID()))
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandMenu("Tabs") {
                Button("Close Tab") {
                    store.send(.closeActiveTabOrWorkspace)
                }
                .keyboardShortcut("w", modifiers: .command)

                ForEach(1..<10) { index in
                    Button("Select Tab \(index)") {
                        store.send(.selectTab(index: index - 1))
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }

            CommandMenu("Board") {
                Button("Toggle Board") {
                    store.send(.toggleBoard)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("Send Terminal Output to Board") {
                    store.send(.sendActiveTerminalOutputToBoard(id: UUID(), createdAt: Date()))
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Paste Most Recent Board Item") {
                    store.send(.pasteMostRecentBoardItemToActiveTerminal)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
