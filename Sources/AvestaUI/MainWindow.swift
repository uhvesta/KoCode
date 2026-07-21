import AvestaCore
import AvestaTerminal
import SwiftUI

public struct MainWindow: View {
    @Bindable private var model: ApplicationModel
    @State private var showingNewWorkspace = false
    @State private var showingAddRepository = false
    @State private var showingRepositoryBank = false

    public init(model: ApplicationModel) { self.model = model }

    public var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(model: model, showingNewWorkspace: $showingNewWorkspace, showingAddRepository: $showingAddRepository, showingRepositoryBank: $showingRepositoryBank)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if let workspace = model.activeWorkspace {
                VStack(spacing: 0) {
                    WorkspaceTabBar(model: model, workspace: workspace)
                    Divider()
                    WorkspaceContent(model: model, workspace: workspace)
                }
                .id(workspace.id)
            } else {
                ContentUnavailableView("No Workspace", systemImage: "folder.badge.plus", description: Text("Create an empty workspace or add one or more repositories."))
            }
        }
        .sheet(isPresented: $showingNewWorkspace) { NewWorkspaceSheet(model: model) }
        .sheet(isPresented: $showingAddRepository) {
            if let workspace = model.activeWorkspace { RepositoryRowsSheet(model: model, workspace: workspace) }
        }
        .sheet(isPresented: $showingRepositoryBank) { RepositoryBankSheet(model: model) }
        .alert("AvestaCode", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { if !model.isLoaded { await model.load() } }
    }
}

private struct WorkspaceContent: View {
    let model: ApplicationModel
    let workspace: WorkspaceRecord

    var body: some View {
        if let primary = workspace.activeTab {
            if let companion = workspace.companionTab, companion.id != primary.id {
                ResizableCompanionSplit(
                    ratio: workspace.layout.splitRatio,
                    primary: { TabContent(model: model, workspace: workspace, tab: primary) },
                    companion: { TabContent(model: model, workspace: workspace, tab: companion) },
                    onRatioChanged: { ratio in Task { await model.updateSplit(workspaceID: workspace.id, ratio: ratio, focusedTabID: nil) } },
                    onClose: { Task { await model.closeCompanion(workspaceID: workspace.id) } }
                )
            } else {
                TabContent(model: model, workspace: workspace, tab: primary)
            }
        } else {
            ContentUnavailableView("No Tabs", systemImage: "rectangle.on.rectangle.slash")
        }
    }
}

private struct TabContent: View {
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    let tab: TabRecord

    var body: some View {
        switch tab.kind {
        case .terminal:
            TerminalSurfaceView(
                tabID: tab.id,
                workingDirectory: tab.workingDirectory ?? workspace.path,
                scrollback: model.terminalScrollback[tab.id] ?? model.globalScrollback,
                pendingInput: model.pendingTerminalInput[tab.id],
                onInputConsumed: { model.consumeTerminalInput(tabID: tab.id, requestID: $0) },
                onFocus: { model.terminalFocused(workspaceID: workspace.id, tabID: tab.id) },
                onEvent: { event in handle(event) },
                onObservedOutput: { output in observe(output) }
            )
            .id(tab.id)
        case .review:
            WorkspaceReviewView(model: model, workspace: workspace)
                .task { if model.reviewStates[workspace.id]?.snapshot == nil { await model.refreshReview(workspaceID: workspace.id, reason: "open") } }
        }
    }

    private func handle(_ event: GhosttyRuntimeEvent) {
        switch event {
        case .notification(let title, let body): Task { await model.terminalOutputObserved(workspaceID: workspace.id, tabID: tab.id, kind: title, summary: body) }
        case .commandFinished(let code): Task { await model.terminalOutputObserved(workspaceID: workspace.id, tabID: tab.id, kind: code == 0 ? "completed" : "failed", summary: "Command exited with status \(code)") }
        case .closeRequested:
            TerminalSurfaceRegistry.shared.release(tabID: tab.id)
            Task { await model.closeTab(tab.id, workspaceID: workspace.id) }
        case .title, .workingDirectory: break
        }
    }

    private func observe(_ output: String) {
        let sanitized = TerminalOutputSanitizer.notificationText(from: output)
        guard sanitized.localizedCaseInsensitiveContains("input required") || sanitized.localizedCaseInsensitiveContains("completed") || sanitized.localizedCaseInsensitiveContains("failed") else { return }
        Task { await model.terminalOutputObserved(workspaceID: workspace.id, tabID: tab.id, kind: "observed", summary: String(sanitized.suffix(240))) }
    }
}

private struct ResizableCompanionSplit<Primary: View, Companion: View>: View {
    let ratio: Double
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let companion: () -> Companion
    let onRatioChanged: (Double) -> Void
    let onClose: () -> Void
    @State private var liveRatio: Double?

    var body: some View {
        GeometryReader { geometry in
            let value = liveRatio ?? ratio
            HStack(spacing: 0) {
                primary().frame(width: max(200, geometry.size.width * value - 3))
                Rectangle().fill(.separator).frame(width: 6).contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { liveRatio = min(0.8, max(0.2, $0.location.x / geometry.size.width)) }.onEnded { _ in if let liveRatio { onRatioChanged(liveRatio) }; liveRatio = nil })
                companion().overlay(alignment: .topTrailing) { Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).padding(8) }
            }
        }
    }
}
