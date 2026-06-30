#if os(macOS)
import AppKit
import QuartzCore

public final class TerminalMetalView: NSView {
    private let metalLayer = CAMetalLayer()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = metalLayer
        metalLayer.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = metalLayer
        metalLayer.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    public override var acceptsFirstResponder: Bool { true }

    public func createSurface() {
        GhosttyApp.shared.initialize()
    }

    public override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }
}
#endif
