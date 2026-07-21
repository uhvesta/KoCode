import AppKit
import AvestaCore
import SwiftUI

struct ReviewCommentFocus: Hashable {
    let repositoryID: UUID
    let filePath: String
    let side: DiffSide
    let line: Int

    func matches(_ annotation: ReviewAnnotation) -> Bool {
        annotation.repositoryID == repositoryID
            && annotation.filePath == filePath
            && annotation.side == side
            && annotation.startLine...annotation.endLine ~= line
    }
}

struct ReviewCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    let initialFocus: ReviewCommentFocus?

    @State private var selectedIDs: Set<UUID> = []
    @State private var showAll = false
    @State private var targetTerminalID: UUID?
    @State private var statusMessage: String?

    private var annotations: [ReviewAnnotation] {
        model.reviewStates[workspace.id]?.annotations ?? []
    }
    private var visibleAnnotations: [ReviewAnnotation] {
        guard !showAll, let initialFocus else { return annotations }
        return annotations.filter(initialFocus.matches)
    }
    private var selectedAnnotations: [ReviewAnnotation] {
        annotations.filter { selectedIDs.contains($0.id) }
    }
    private var terminals: [TabRecord] { workspace.tabs.filter { $0.kind == .terminal } }
    private var bundle: String {
        WorkspaceReviewBundleFormatter.format(workspace: workspace, annotations: selectedAnnotations)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Review Comments", systemImage: "text.bubble")
                    .font(.title3.bold())
                Text("\(annotations.count)").foregroundStyle(.secondary)
                if initialFocus != nil && !showAll {
                    Text("Showing comments on the selected line").font(.caption).foregroundStyle(.secondary)
                    Button("Show All") { showAll = true }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()

            if annotations.isEmpty {
                ContentUnavailableView(
                    "No Comments",
                    systemImage: "text.bubble",
                    description: Text("Select one or more lines in Review and choose Add Comment.")
                )
            } else {
                HSplitView {
                    commentList.frame(minWidth: 420, idealWidth: 500)
                    exportPreview.frame(minWidth: 400, idealWidth: 520)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onAppear {
            selectedIDs = Set(annotations.map(\.id))
            targetTerminalID = preferredTerminalID
        }
        .onChange(of: annotations.map(\.id)) { _, ids in
            selectedIDs.formIntersection(ids)
        }
    }

    private var commentList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments").font(.headline)
                Spacer()
                Button(selectedIDs.count == annotations.count ? "Select None" : "Select All") {
                    selectedIDs = selectedIDs.count == annotations.count ? [] : Set(annotations.map(\.id))
                }
                .buttonStyle(.link)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(visibleAnnotations) { annotation in
                        ReviewCommentCard(
                            model: model,
                            workspace: workspace,
                            annotation: annotation,
                            isIncluded: Binding(
                                get: { selectedIDs.contains(annotation.id) },
                                set: { included in
                                    if included { selectedIDs.insert(annotation.id) }
                                    else { selectedIDs.remove(annotation.id) }
                                }
                            )
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private var exportPreview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Combined Message").font(.headline)
                Text("\(selectedAnnotations.count) included").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                Text(selectedAnnotations.isEmpty ? "Select at least one comment to build a message." : bundle)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let statusMessage {
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        copyBundle()
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                    .disabled(selectedAnnotations.isEmpty)
                    Spacer()
                }
                HStack {
                    Picker("Terminal", selection: $targetTerminalID) {
                        Text("Choose a terminal").tag(UUID?.none)
                        ForEach(terminals) { terminal in
                            Text(terminalLabel(terminal)).tag(UUID?.some(terminal.id))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Button("Send to Terminal") { sendToTerminal() }
                        .disabled(selectedAnnotations.isEmpty || targetTerminalID == nil)
                }
                Text("Sending inserts the message through Ghostty. It does not press Enter or execute it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var preferredTerminalID: UUID? {
        if let last = model.lastFocusedTerminalID[workspace.id], terminals.contains(where: { $0.id == last }) { return last }
        return terminals.first?.id
    }

    private func terminalLabel(_ terminal: TabRecord) -> String {
        guard let directory = terminal.workingDirectory?.lastPathComponent, !directory.isEmpty else { return terminal.title }
        return "\(terminal.title) — \(directory)"
    }

    private func copyBundle() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bundle, forType: .string)
        statusMessage = "Copied \(selectedAnnotations.count) comment\(selectedAnnotations.count == 1 ? "" : "s") to the clipboard."
    }

    private func sendToTerminal() {
        guard let targetTerminalID,
              let terminal = terminals.first(where: { $0.id == targetTerminalID }) else { return }
        if model.sendReviewBundleToTerminal(workspaceID: workspace.id, annotations: selectedAnnotations, targetTabID: targetTerminalID) {
            statusMessage = "Inserted into \(terminal.title) without executing."
        }
    }
}

private struct ReviewCommentCard: View {
    let model: ApplicationModel
    let workspace: WorkspaceRecord
    let annotation: ReviewAnnotation
    @Binding var isIncluded: Bool

    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmingDelete = false

    private var repositoryName: String {
        workspace.repositories.first { $0.id == annotation.repositoryID }?.name ?? "Unknown repository"
    }
    private var lineLabel: String {
        annotation.startLine == annotation.endLine
            ? "\(annotation.side.rawValue) line \(annotation.startLine)"
            : "\(annotation.side.rawValue) lines \(annotation.startLine)–\(annotation.endLine)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Toggle("Include", isOn: $isIncluded).labelsHidden()
                Text(repositoryName).font(.caption).foregroundStyle(.secondary)
                Text(annotation.filePath).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if annotation.isOutdated { Text("Outdated").font(.caption2).foregroundStyle(.orange) }
                Text(lineLabel).font(.caption).foregroundStyle(.secondary)
            }

            Text(annotation.selectedCode.isEmpty ? "(No source excerpt)" : annotation.selectedCode)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)

            if isEditing {
                TextEditor(text: $draft).frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false }
                    Button("Save") {
                        Task {
                            if await model.updateAnnotationText(annotation, text: draft) { isEditing = false }
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text(annotation.userText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if let response = annotation.response, !response.isEmpty {
                    Text(response).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Text(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Edit") { draft = annotation.userText; isEditing = true }
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .alert("Delete Comment?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { _ = await model.deleteAnnotation(annotation) } }
        } message: {
            Text("This permanently removes the comment and any associated assistant thread.")
        }
    }
}
