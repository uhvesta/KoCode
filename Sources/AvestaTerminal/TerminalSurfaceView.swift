#if os(macOS)
import AvestaCore
import SwiftUI

public struct TerminalSurfaceView: NSViewRepresentable {
    public let workingDirectory: URL
    public let tabID: UUID
    public let pendingPaste: String?
    public let resume: TerminalResumeSnapshot?
    public var onOutput: (String) -> Void
    public var onPasteConsumed: () -> Void

    public init(
        workingDirectory: URL,
        tabModel: TerminalTabModel,
        onOutput: @escaping (String) -> Void = { _ in }
    ) {
        self.workingDirectory = workingDirectory
        self.tabID = tabModel.id
        self.pendingPaste = tabModel.pendingPaste
        self.resume = tabModel.resume
        self.onOutput = onOutput
        self.onPasteConsumed = {}
    }

    public init(
        workingDirectory: URL,
        tabID: UUID,
        pendingPaste: String?,
        resume: TerminalResumeSnapshot?,
        onOutput: @escaping (String) -> Void = { _ in },
        onPasteConsumed: @escaping () -> Void = {}
    ) {
        self.workingDirectory = workingDirectory
        self.tabID = tabID
        self.pendingPaste = pendingPaste
        self.resume = resume
        self.onOutput = onOutput
        self.onPasteConsumed = onPasteConsumed
    }

    public func makeNSView(context: Context) -> TerminalMetalView {
        let view = TerminalMetalView()
        view.createSurface(
            workingDirectory: workingDirectory,
            startupInput: resume.map { $0.command + "\n" },
            onOutput: { output in
                onOutput(output)
            },
            onExit: {}
        )
        return view
    }

    public func updateNSView(_ nsView: TerminalMetalView, context: Context) {
        nsView.toolTip = workingDirectory.path
        if let pendingPaste {
            nsView.paste(pendingPaste)
            onPasteConsumed()
        }
    }

    public final class Coordinator {
        public init() {}
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
#else
import AvestaCore
import SwiftUI

public struct TerminalSurfaceView: View {
    public let workingDirectory: URL
    public let tabID: UUID
    public let pendingPaste: String?
    public let resume: TerminalResumeSnapshot?
    public var onOutput: (String) -> Void
    public var onPasteConsumed: () -> Void

    public init(workingDirectory: URL, tabModel: TerminalTabModel, onOutput: @escaping (String) -> Void = { _ in }) {
        self.workingDirectory = workingDirectory
        self.tabID = tabModel.id
        self.pendingPaste = tabModel.pendingPaste
        self.resume = tabModel.resume
        self.onOutput = onOutput
        self.onPasteConsumed = {}
    }

    public init(
        workingDirectory: URL,
        tabID: UUID,
        pendingPaste: String?,
        resume: TerminalResumeSnapshot?,
        onOutput: @escaping (String) -> Void = { _ in },
        onPasteConsumed: @escaping () -> Void = {}
    ) {
        self.workingDirectory = workingDirectory
        self.tabID = tabID
        self.pendingPaste = pendingPaste
        self.resume = resume
        self.onOutput = onOutput
        self.onPasteConsumed = onPasteConsumed
    }

    public var body: some View {
        Text("Terminal unavailable on this platform")
    }
}
#endif
