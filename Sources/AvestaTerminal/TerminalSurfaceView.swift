#if os(macOS)
import AvestaCore
import SwiftUI

public struct TerminalSurfaceView: NSViewRepresentable {
    public let workingDirectory: URL
    public let tabModel: TerminalTabModel

    public init(workingDirectory: URL, tabModel: TerminalTabModel) {
        self.workingDirectory = workingDirectory
        self.tabModel = tabModel
    }

    public func makeNSView(context: Context) -> TerminalMetalView {
        let view = TerminalMetalView()
        view.createSurface()
        return view
    }

    public func updateNSView(_ nsView: TerminalMetalView, context: Context) {
        nsView.toolTip = workingDirectory.path
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

    public init(workingDirectory: URL, tabModel: TerminalTabModel) {
        self.workingDirectory = workingDirectory
        self.tabModel = tabModel
    }

    public var body: some View {
        Text("Terminal unavailable on this platform")
    }
}
#endif
