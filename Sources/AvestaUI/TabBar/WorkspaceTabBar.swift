import AvestaCore
import AvestaTerminal
import SwiftUI

struct WorkspaceTabBar: View {
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    @State private var draggedTabID: UUID?
    @State private var renamingTab: TabRecord?
    @State private var renameTitle = ""

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 2) {
                    ForEach(workspace.tabs) { tab in
                        tabButton(tab)
                            .onDrag { draggedTabID = tab.id; return NSItemProvider(object: tab.id.uuidString as NSString) }
                            .onDrop(of: [.text], delegate: TabDropDelegate(targetID: tab.id, draggedID: $draggedTabID) { source, target in Task { await model.moveTab(workspaceID: workspace.id, tabID: source, before: target) } })
                    }
                }.padding(.horizontal, 6)
            }
            newTabMenu
        }
        .frame(height: 38)
        .background(.bar)
        .alert("Rename Tab", isPresented: Binding(get: { renamingTab != nil }, set: { if !$0 { renamingTab = nil } })) {
            TextField("Title", text: $renameTitle)
            Button("Cancel", role: .cancel) { renamingTab = nil }
            Button("Rename") { if let tab = renamingTab { Task { await model.renameTab(id: tab.id, title: renameTitle) } }; renamingTab = nil }
        }
    }

    private func tabButton(_ tab: TabRecord) -> some View {
        Button { Task { await model.selectTab(workspaceID: workspace.id, tabID: tab.id) } } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.kind == .terminal ? "terminal" : "doc.text.magnifyingglass")
                Text(tab.title).lineLimit(1)
                Button { close(tab) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(workspace.layout.primaryTabID == tab.id ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") { renamingTab = tab; renameTitle = tab.title }
            Button("Open Beside") { Task { await model.openBeside(tabID: tab.id, workspaceID: workspace.id) } }
            if tab.kind == .terminal {
                Menu("Scrollback") {
                    Button("Disabled") { setScrollback(tab, .disabled) }
                    Button("10,000 Lines") { setScrollback(tab, .limited(lines: 10_000)) }
                    Button("Unlimited") { setScrollback(tab, .unlimited) }
                }
            }
            Divider()
            Button("Close") { close(tab) }
            Button("Close Others") {
                for other in workspace.tabs where other.id != tab.id && other.kind == .terminal { TerminalSurfaceRegistry.shared.release(tabID: other.id) }
                Task { await model.closeOtherTabs(keeping: tab.id, workspaceID: workspace.id) }
            }
        }
    }

    private var newTabMenu: some View {
        Menu {
            Menu("New Terminal") {
                Button("Workspace Root") { Task { _ = await model.createTab(kind: .terminal, workspaceID: workspace.id, workingDirectory: workspace.path) } }
                ForEach(workspace.repositories) { repository in Button(repository.name) { Task { _ = await model.createTab(kind: .terminal, workspaceID: workspace.id, workingDirectory: repository.worktreePath) } } }
            }
            Menu("New Terminal Beside") {
                Button("Workspace Root") { Task { _ = await model.createTab(kind: .terminal, workspaceID: workspace.id, workingDirectory: workspace.path, beside: true) } }
                ForEach(workspace.repositories) { repository in Button(repository.name) { Task { _ = await model.createTab(kind: .terminal, workspaceID: workspace.id, workingDirectory: repository.worktreePath, beside: true) } } }
            }
            Button("New Review") { Task { _ = await model.createTab(kind: .review, workspaceID: workspace.id) } }
            Button("New Review Beside") { Task { _ = await model.createTab(kind: .review, workspaceID: workspace.id, beside: true) } }
        } label: { Image(systemName: "plus").frame(width: 34, height: 34) }
        .menuStyle(.borderlessButton)
        .frame(width: 42)
    }

    private func close(_ tab: TabRecord) {
        if tab.kind == .terminal { TerminalSurfaceRegistry.shared.release(tabID: tab.id) }
        Task { await model.closeTab(tab.id, workspaceID: workspace.id) }
    }

    private func setScrollback(_ tab: TabRecord, _ policy: ScrollbackPolicy) {
        TerminalSurfaceRegistry.shared.updateScrollback(tabID: tab.id, policy: policy)
        Task { await model.setTerminalScrollback(tabID: tab.id, policy: policy) }
    }
}

private struct TabDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let source = draggedID, source != targetID else { return }
        move(source, targetID)
    }
    func performDrop(info: DropInfo) -> Bool { draggedID = nil; return true }
}
