import AppKit
import AvestaCore
import AvestaNotifications
import AvestaTerminal
import AvestaUI
import SwiftUI

@main
struct AvestaCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: ApplicationModel
    @State private var notifications = NotificationService()

    init() {
        _model = State(initialValue: try! ApplicationModel())
    }

    var body: some Scene {
        WindowGroup { MainWindow(model: model).task { await notifications.requestPermission() } }
            .commands {
                CommandGroup(after: .newItem) {
                    Button("New Terminal") { createTab(.terminal, beside: false) }.keyboardShortcut("t", modifiers: .command)
                    Button("New Review") { createTab(.review, beside: false) }.keyboardShortcut("r", modifiers: [.command, .shift])
                    Divider()
                    Button("New Terminal Beside") { createTab(.terminal, beside: true) }.keyboardShortcut("t", modifiers: [.command, .option])
                    Button("New Review Beside") { createTab(.review, beside: true) }.keyboardShortcut("r", modifiers: [.command, .option])
                }
                CommandMenu("Workspace") {
                    Button("Start New Workspace Session") { if let id = model.activeWorkspace?.id { Task { await model.startNewActivitySession(workspaceID: id) } } }
                    Button("Refresh Review") { if let id = model.activeWorkspace?.id { Task { await model.refreshReview(workspaceID: id) } } }.keyboardShortcut("r", modifiers: .command)
                }
                CommandMenu("Tabs") {
                    Button("Close Tab") { closeActiveTab() }
                        .keyboardShortcut("w", modifiers: .command)
                        .disabled(model.activeWorkspace?.activeTab == nil)
                    Divider()
                    Button("Previous Tab") { selectAdjacentTab(offset: -1) }
                        .keyboardShortcut("[", modifiers: [.command, .shift])
                        .disabled((model.activeWorkspace?.tabs.count ?? 0) < 2)
                    Button("Next Tab") { selectAdjacentTab(offset: 1) }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                        .disabled((model.activeWorkspace?.tabs.count ?? 0) < 2)
                    Divider()
                    ForEach(1...9, id: \.self) { number in
                        Button(number == 9 ? "Select Last Tab" : "Select Tab \(number)") {
                            selectTab(shortcutNumber: number)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
                        .disabled(tabID(shortcutNumber: number) == nil)
                    }
                }
            }

        Settings { SettingsView(model: model) }
    }

    private func createTab(_ kind: TabKind, beside: Bool) {
        guard let workspace = model.activeWorkspace else { return }
        Task { _ = await model.createTab(kind: kind, workspaceID: workspace.id, workingDirectory: workspace.path, beside: beside) }
    }

    private func closeActiveTab() {
        guard let workspace = model.activeWorkspace, let tab = workspace.activeTab else { return }
        if tab.kind == .terminal { TerminalSurfaceRegistry.shared.release(tabID: tab.id) }
        Task { await model.closeTab(tab.id, workspaceID: workspace.id) }
    }

    private func selectAdjacentTab(offset: Int) {
        guard let workspace = model.activeWorkspace, let tabID = workspace.adjacentTabID(offset: offset) else { return }
        Task { await model.selectTab(workspaceID: workspace.id, tabID: tabID) }
    }

    private func tabID(shortcutNumber: Int) -> UUID? {
        model.activeWorkspace?.tabID(shortcutNumber: shortcutNumber)
    }

    private func selectTab(shortcutNumber: Int) {
        guard let workspace = model.activeWorkspace, let tabID = workspace.tabID(shortcutNumber: shortcutNumber) else { return }
        Task { await model.selectTab(workspaceID: workspace.id, tabID: tabID) }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM-launched executables can otherwise remain a background app with
        // a WindowGroup that was created but never brought onscreen.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) { GhosttyApp.shared.shutdown() }
}
