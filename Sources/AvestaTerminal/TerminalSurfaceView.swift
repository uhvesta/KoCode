#if os(macOS)
import AvestaCore
import SwiftUI

public struct TerminalSurfaceView: NSViewRepresentable {
    public let workingDirectory: URL
    public let tabModel: TerminalTabModel
    public var onOutput: (String) -> Void

    public init(
        workingDirectory: URL,
        tabModel: TerminalTabModel,
        onOutput: @escaping (String) -> Void = { _ in }
    ) {
        self.workingDirectory = workingDirectory
        self.tabModel = tabModel
        self.onOutput = onOutput
    }

    public func makeNSView(context: Context) -> TerminalMetalView {
        let view = TerminalMetalView()
        view.createSurface(
            workingDirectory: workingDirectory,
            startupInput: tabModel.resume.map { $0.command + "\n" },
            onOutput: { output in
                tabModel.appendOutput(output)
                onOutput(output)
            },
            onExit: {
                tabModel.isProcessRunning = false
            }
        )
        return view
    }

    public func updateNSView(_ nsView: TerminalMetalView, context: Context) {
        nsView.toolTip = workingDirectory.path
        if let pendingPaste = tabModel.pendingPaste {
            nsView.paste(pendingPaste)
            tabModel.pendingPaste = nil
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
    public let tabModel: TerminalTabModel
    public var onOutput: (String) -> Void

    public init(workingDirectory: URL, tabModel: TerminalTabModel, onOutput: @escaping (String) -> Void = { _ in }) {
        self.workingDirectory = workingDirectory
        self.tabModel = tabModel
        self.onOutput = onOutput
    }

    public var body: some View {
        Text("Terminal unavailable on this platform")
    }
}
#endif
