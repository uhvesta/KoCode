#if os(macOS)
import AvestaCore
import SwiftUI

public struct TerminalSurfaceView: NSViewRepresentable {
    public let tabID: UUID
    public let workingDirectory: URL
    public let startupInput: String?
    public let scrollback: ScrollbackPolicy
    public let pendingInput: TerminalInputRequest?
    public var onInputConsumed: (UUID) -> Void
    public var onFocus: () -> Void
    public var onEvent: (GhosttyRuntimeEvent) -> Void
    public var onObservedOutput: (String) -> Void

    public init(tabID: UUID, workingDirectory: URL, startupInput: String? = nil, scrollback: ScrollbackPolicy = .limited(lines: 10_000), pendingInput: TerminalInputRequest? = nil, onInputConsumed: @escaping (UUID) -> Void = { _ in }, onFocus: @escaping () -> Void = {}, onEvent: @escaping (GhosttyRuntimeEvent) -> Void = { _ in }, onObservedOutput: @escaping (String) -> Void = { _ in }) {
        self.tabID = tabID
        self.workingDirectory = workingDirectory
        self.startupInput = startupInput
        self.scrollback = scrollback
        self.pendingInput = pendingInput
        self.onInputConsumed = onInputConsumed
        self.onFocus = onFocus
        self.onEvent = onEvent
        self.onObservedOutput = onObservedOutput
    }

    public func makeNSView(context: Context) -> TerminalMetalView {
        TerminalSurfaceRegistry.shared.view(tabID: tabID, workingDirectory: workingDirectory, startupInput: startupInput, scrollback: scrollback, onFocus: onFocus, onEvent: onEvent, onObservedOutput: onObservedOutput)
    }

    public func updateNSView(_ view: TerminalMetalView, context: Context) {
        view.updateHandlers(onFocus: onFocus, onEvent: onEvent, onObservedOutput: onObservedOutput)
        if let pendingInput, context.coordinator.lastInputID != pendingInput.id {
            view.insertReviewText(pendingInput.text)
            context.coordinator.lastInputID = pendingInput.id
            onInputConsumed(pendingInput.id)
        }
        if view.window?.firstResponder === view { onFocus() }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }
    public final class Coordinator { var lastInputID: UUID? }

    public static func dismantleNSView(_ nsView: TerminalMetalView, coordinator: Coordinator) {
        // The tab-scoped registry intentionally keeps the live Ghostty surface across tab
        // selection and companion docking. Permanent tab close releases it explicitly.
    }
}
#else
import AvestaCore
import SwiftUI
public struct TerminalSurfaceView: View {
    public init(tabID: UUID, workingDirectory: URL, startupInput: String? = nil, scrollback: ScrollbackPolicy = .limited(lines: 10_000), pendingInput: TerminalInputRequest? = nil, onInputConsumed: @escaping (UUID) -> Void = { _ in }, onFocus: @escaping () -> Void = {}, onEvent: @escaping (GhosttyRuntimeEvent) -> Void = { _ in }, onObservedOutput: @escaping (String) -> Void = { _ in }) {}
    public var body: some View { Text("Terminal unavailable") }
}
public enum GhosttyRuntimeEvent: Sendable { case closeRequested }
#endif
