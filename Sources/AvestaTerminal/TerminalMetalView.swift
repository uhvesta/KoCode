#if os(macOS)
import AppKit
import AvestaCore
import Carbon.HIToolbox
import GhosttyKit
import QuartzCore

enum TerminalInputMapping {
    /// AppKit reports view-local points from the bottom-left. libghostty's
    /// macOS surface API expects logical (not backing-pixel) coordinates from
    /// the top-left. Keeping this conversion independent of the display scale
    /// prevents selections from jumping when a window moves between screens.
    static func ghosttyMousePosition(viewPoint: CGPoint, boundsHeight: CGFloat) -> CGPoint {
        CGPoint(x: viewPoint.x, y: boundsHeight - viewPoint.y)
    }

    /// Returns the text associated with a key event. This is deliberately the
    /// text field of `ghostty_input_key_s`, never a direct PTY write. Ghostty
    /// needs the physical key and modifier bits as well as this value to apply
    /// terminal key bindings (for example Ctrl-C -> SIGINT).
    static func text(
        modifiers: NSEvent.ModifierFlags,
        characters: String?,
        charactersIgnoringModifiers: String?
    ) -> String? {
        guard !modifiers.contains(.command) else { return nil }

        // AppKit's `characters` is often the already-translated control byte
        // for Ctrl-C, Ctrl-D, etc. Ghostty's key API expects the printable
        // key text ("c", "d", ...) together with GHOSTTY_MODS_CTRL.
        if modifiers.contains(.control) {
            guard let value = charactersIgnoringModifiers, !value.isEmpty else { return nil }
            return value
        }

        guard let value = characters, !value.isEmpty else { return nil }
        // Native control keys are represented by their physical Ghostty key,
        // not by a control byte in `key.text`. Passing "\r", "\u{8}", or
        // "\u{7F}" as text makes the text-input path insert/echo characters
        // instead of invoking Return/Backspace/Delete terminal semantics.
        if value.unicodeScalars.allSatisfy({ $0.value <= 0x1F || $0.value == 0x7F }) {
            return nil
        }
        // Arrows, Home/End, and the function/navigation keys use AppKit's
        // private-use Unicode values. They must be represented by keycode,
        // not sent through Ghostty's text path.
        if value.unicodeScalars.contains(where: { $0.value >= 0xE000 && $0.value <= 0xF8FF }) {
            return nil
        }
        return value
    }

    /// libghostty's macOS surface API expects the platform virtual keycode in
    /// `ghostty_input_key_s.keycode`. `ghostty_input_key_e` is a different
    /// namespace used by binding triggers; putting those enum values here
    /// changes the physical key (Backspace could become Space, for example).
    static func ghosttyKeyCode(for appKitVirtualKeyCode: UInt16) -> UInt32 {
        UInt32(appKitVirtualKeyCode)
    }

    static func unshiftedCodepoint(for charactersIgnoringModifiers: String?) -> UInt32 {
        let scalar = charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        if scalar <= 0x1F || scalar == 0x7F || (scalar >= 0xE000 && scalar <= 0xF8FF) { return 0 }
        return scalar
    }

    static func ghosttyModifiers(for flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        if flags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { raw |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if flags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0 { raw |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if flags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0 { raw |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if flags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0 { raw |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    static func consumedModifiers(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    static func translationModifierFlags(
        original flags: NSEvent.ModifierFlags,
        ghosttyTranslationMods: ghostty_input_mods_e
    ) -> NSEvent.ModifierFlags {
        var translated = flags
        let pairs: [(NSEvent.ModifierFlags, ghostty_input_mods_e)] = [
            (.shift, GHOSTTY_MODS_SHIFT),
            (.control, GHOSTTY_MODS_CTRL),
            (.option, GHOSTTY_MODS_ALT),
            (.command, GHOSTTY_MODS_SUPER),
        ]
        for (flag, ghosttyFlag) in pairs {
            if ghosttyTranslationMods.rawValue & ghosttyFlag.rawValue != 0 {
                translated.insert(flag)
            } else {
                translated.remove(flag)
            }
        }
        return translated
    }

    static func modifierAction(
        keyCode: UInt16,
        modifierFlagsRawValue rawValue: UInt
    ) -> ghostty_input_action_e? {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        let modifierActive: Bool
        switch keyCode {
        case 0x39: modifierActive = flags.contains(.capsLock)
        case 0x38, 0x3C: modifierActive = flags.contains(.shift)
        case 0x3B, 0x3E: modifierActive = flags.contains(.control)
        case 0x3A, 0x3D: modifierActive = flags.contains(.option)
        case 0x37, 0x36: modifierActive = flags.contains(.command)
        default: return nil
        }
        guard modifierActive else { return GHOSTTY_ACTION_RELEASE }

        let sidePressed: Bool
        switch keyCode {
        case 0x38: sidePressed = rawValue & UInt(NX_DEVICELSHIFTKEYMASK) != 0
        case 0x3C: sidePressed = rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
        case 0x3B: sidePressed = rawValue & UInt(NX_DEVICELCTLKEYMASK) != 0
        case 0x3E: sidePressed = rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
        case 0x3A: sidePressed = rawValue & UInt(NX_DEVICELALTKEYMASK) != 0
        case 0x3D: sidePressed = rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
        case 0x37: sidePressed = rawValue & UInt(NX_DEVICELCMDKEYMASK) != 0
        case 0x36: sidePressed = rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
        default: sidePressed = true
        }
        return sidePressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    }

    /// Workspace commands belong to the application menu, not the embedded
    /// terminal. Returning false for these in `performKeyEquivalent` lets
    /// AppKit continue routing them to SwiftUI's Commands scene.
    static func isWorkspaceShortcut(
        modifiers: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        let flags = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        let key = charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == [.command] {
            return key == "t" || key == "w" || key == "r" || ("1"..."9").contains(key)
        }
        if flags == [.command, .shift] {
            return key == "[" || key == "]" || key == "r"
        }
        if flags == [.command, .option] {
            return key == "t" || key == "r"
        }
        return false
    }
}

@MainActor
public final class TerminalSurfaceRegistry {
    public static let shared = TerminalSurfaceRegistry()
    private var views: [UUID: TerminalMetalView] = [:]

    private init() {}

    public func view(
        tabID: UUID,
        workingDirectory: URL,
        startupInput: String?,
        scrollback: ScrollbackPolicy,
        onFocus: @escaping @MainActor () -> Void,
        onEvent: @escaping @MainActor (GhosttyRuntimeEvent) -> Void,
        onObservedOutput: @escaping @MainActor (String) -> Void
    ) -> TerminalMetalView {
        if let existing = views[tabID] {
            existing.updateHandlers(onFocus: onFocus, onEvent: onEvent, onObservedOutput: onObservedOutput)
            return existing
        }
        let view = TerminalMetalView(tabID: tabID)
        view.configureSurface(workingDirectory: workingDirectory, startupInput: startupInput, scrollback: scrollback, onFocus: onFocus, onEvent: onEvent, onObservedOutput: onObservedOutput)
        views[tabID] = view
        return view
    }

    public func release(tabID: UUID) {
        views.removeValue(forKey: tabID)?.closeSurface()
    }

    public func updateScrollback(tabID: UUID, policy: ScrollbackPolicy) { views[tabID]?.updateScrollback(policy) }

    public func releaseAll() {
        let retained = views.values
        views.removeAll()
        retained.forEach { $0.closeSurface() }
    }

    public var activeSurfaceCount: Int { views.values.filter(\.hasLiveSurface).count }
}

public final class TerminalMetalView: NSView, NSTextInputClient {
    public let tabID: UUID
    private var surface: ghostty_surface_t?
    private var bridge: GhosttySurfaceBridge?
    private var bridgePointer: UnsafeMutableRawPointer?
    private var outputTee: Unmanaged<TerminalOutputObserver>?
    private var workingDirectory: URL?
    private var startupInput: String?
    private var scrollback: ScrollbackPolicy = .limited(lines: 10_000)
    private var onEvent: @MainActor (GhosttyRuntimeEvent) -> Void = { _ in }
    private var onObservedOutput: @MainActor (String) -> Void = { _ in }
    private var onFocus: @MainActor () -> Void = {}
    private var trackingArea: NSTrackingArea?
    private var markedText = NSAttributedString()
    private var surfaceClosed = false
    public var isCursorHiddenByTerminal = false { didSet { updateCursorVisibility() } }

    public var hasLiveSurface: Bool { surface != nil && !surfaceClosed }
    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }
    public func hasMarkedText() -> Bool { markedText.length > 0 }
    public func markedRange() -> NSRange { hasMarkedText() ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0) }
    public func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    public var conversationIdentifier: Int { ObjectIdentifier(self).hashValue }

    public init(tabID: UUID) {
        self.tabID = tabID
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    public required init?(coder: NSCoder) { nil }

    deinit {
        // Registry ownership means deinit only happens after a permanent tab close or app shutdown.
        MainActor.assumeIsolated { closeSurface() }
    }

    public override func makeBackingLayer() -> CALayer {
        let metal = CAMetalLayer()
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = false
        metal.isOpaque = true
        return metal
    }

    public func configureSurface(workingDirectory: URL, startupInput: String?, scrollback: ScrollbackPolicy, onFocus: @escaping @MainActor () -> Void, onEvent: @escaping @MainActor (GhosttyRuntimeEvent) -> Void, onObservedOutput: @escaping @MainActor (String) -> Void) {
        self.workingDirectory = workingDirectory
        self.startupInput = startupInput
        self.scrollback = scrollback
        self.onFocus = onFocus
        self.onEvent = onEvent
        self.onObservedOutput = onObservedOutput
        createSurfaceIfNeeded()
    }

    public func updateHandlers(onFocus: @escaping @MainActor () -> Void, onEvent: @escaping @MainActor (GhosttyRuntimeEvent) -> Void, onObservedOutput: @escaping @MainActor (String) -> Void) {
        self.onFocus = onFocus
        self.onEvent = onEvent
        self.onObservedOutput = onObservedOutput
    }

    public func insertReviewText(_ text: String) { sendText(text) }
    public func pasteText(_ text: String) { sendText(text) }

    public func updateScrollback(_ policy: ScrollbackPolicy) {
        scrollback = policy
        guard let surface, let configuration = GhosttyApp.shared.configuration(scrollbackValue: policy.ghosttyConfigurationValue) else { return }
        ghostty_surface_update_config(surface, configuration)
        ghostty_config_free(configuration)
    }

    public func closeSurface() {
        guard !surfaceClosed else { return }
        surfaceClosed = true
        if let surface {
            ghostty_surface_set_pty_tee_cb(surface, nil, nil)
            GhosttyApp.shared.unregister(surface: surface)
            ghostty_surface_free(surface)
        }
        surface = nil
        bridge?.surface = nil
        bridge = nil
        bridgePointer = nil
        outputTee?.release()
        outputTee = nil
    }

    public func refreshSurface() {
        if let surface { ghostty_surface_refresh(surface) }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        createSurfaceIfNeeded()
        if window != nil, let app = GhosttyApp.shared.app { ghostty_app_set_focus(app, true) }
        updateGeometry()
        updateVisibility()
    }

    public override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateGeometry() }
    public override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateGeometry() }
    public override func viewDidHide() { super.viewDidHide(); updateVisibility() }
    public override func viewDidUnhide() { super.viewDidUnhide(); updateVisibility() }

    public override func becomeFirstResponder() -> Bool {
        if let app = GhosttyApp.shared.app { ghostty_app_set_focus(app, true) }
        if let surface { ghostty_surface_set_focus(surface, true) }
        onFocus()
        return true
    }

    public override func resignFirstResponder() -> Bool {
        if let surface { ghostty_surface_set_focus(surface, false) }
        if let app = GhosttyApp.shared.app { ghostty_app_set_focus(app, false) }
        return true
    }

    public override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    public override func keyDown(with event: NSEvent) {
        _ = sendKeyEvent(event)
    }

    /// Shared production/test boundary for keyboard input. Tests can drive
    /// this method with synthetic NSEvents while still exercising the exact
    /// libghostty key struct used by AppKit's responder path.
    @discardableResult
    internal func sendKeyEvent(_ event: NSEvent) -> Bool {
        guard let surface else { return false }
        ghostty_surface_set_focus(surface, true)
        let originalMods = ghosttyModifiers(event.modifierFlags)
        let translationMods = ghostty_surface_key_translation_mods(surface, originalMods)
        let translatedFlags = TerminalInputMapping.translationModifierFlags(
            original: event.modifierFlags,
            ghosttyTranslationMods: translationMods
        )
        let translatedEvent = translatedKeyEvent(from: event, modifierFlags: translatedFlags)
        var key = ghosttyKey(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
        key.consumed_mods = TerminalInputMapping.consumedModifiers(from: translatedFlags)
        key.unshifted_codepoint = TerminalInputMapping.unshiftedCodepoint(
            for: translatedEvent.charactersIgnoringModifiers ?? translatedEvent.characters
        )
        if let characters = TerminalInputMapping.text(
            modifiers: translatedFlags,
            characters: translatedEvent.characters,
            charactersIgnoringModifiers: translatedEvent.charactersIgnoringModifiers
        ) {
            return characters.withCString { pointer in key.text = pointer; return ghostty_surface_key(surface, key) }
        } else {
            key.consumed_mods = GHOSTTY_MODS_NONE
            return ghostty_surface_key(surface, key)
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let surface else {
            return super.performKeyEquivalent(with: event)
        }
        if TerminalInputMapping.isWorkspaceShortcut(
            modifiers: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        ) {
            return false
        }
        // Do not let AppKit's default-button/focus handling swallow Return,
        // Tab, Control, Option, or navigation keys. They must reach keyDown
        // and then libghostty. Command equivalents are handled below.
        guard event.modifierFlags.contains(.command) else { return false }
        if event.charactersIgnoringModifiers?.lowercased() == "v" {
            let pasted = NSPasteboard.general.string(forType: .string) ?? ""
            if !pasted.isEmpty {
                pasted.withCString { ghostty_surface_text_input(surface, $0, UInt(pasted.utf8.count)) }
            }
            return true
        }
        var key = ghosttyKey(event, action: GHOSTTY_ACTION_PRESS)
        key.text = nil
        return ghostty_surface_key(surface, key)
    }

    public override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        var key = ghosttyKey(event, action: GHOSTTY_ACTION_RELEASE)
        key.text = nil
        _ = ghostty_surface_key(surface, key)
    }

    public override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        guard let action = TerminalInputMapping.modifierAction(
            keyCode: event.keyCode,
            modifierFlagsRawValue: event.modifierFlags.rawValue
        ) else {
            super.flagsChanged(with: event)
            return
        }
        var key = ghosttyKey(event, action: action)
        key.text = nil
        key.composing = false
        key.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, key)
    }

    public override func mouseDown(with event: NSEvent) {
        // Updating the pointer again on a double/triple click can move the
        // selection anchor between clicks. This matches Ghostty's macOS host.
        sendMouse(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT, updatePosition: event.clickCount == 1)
    }
    public override func mouseUp(with event: NSEvent) { sendMouse(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT, updatePosition: false) }
    public override func rightMouseDown(with event: NSEvent) { sendMouse(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT, updatePosition: true) }
    public override func rightMouseUp(with event: NSEvent) { sendMouse(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT, updatePosition: false) }
    public override func otherMouseDown(with event: NSEvent) { sendMouse(event, state: GHOSTTY_MOUSE_PRESS, button: mouseButton(event.buttonNumber), updatePosition: true) }
    public override func otherMouseUp(with event: NSEvent) { sendMouse(event, state: GHOSTTY_MOUSE_RELEASE, button: mouseButton(event.buttonNumber), updatePosition: false) }
    public override func mouseMoved(with event: NSEvent) { sendMousePosition(event) }
    public override func mouseDragged(with event: NSEvent) { sendMousePosition(event) }
    public override func rightMouseDragged(with event: NSEvent) { sendMousePosition(event) }
    public override func otherMouseDragged(with event: NSEvent) { sendMousePosition(event) }

    public override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        sendMousePosition(event)
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, Int32(ghosttyModifiers(event.modifierFlags).rawValue))
    }

    public override func pressureChange(with event: NSEvent) {
        if let surface { ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure)) }
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        let value = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = NSAttributedString()
        sendCommittedText(value)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString) ?? NSAttributedString(string: (string as? String) ?? "")
        guard let surface else { return }
        markedText.string.withCString { ghostty_surface_preedit(surface, $0, UInt(markedText.string.utf8.count)) }
    }

    public func unmarkText() {
        markedText = NSAttributedString()
        guard let surface else { return }
        ghostty_surface_preedit(surface, "", 0)
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func characterIndex(for point: NSPoint) -> Int { 0 }
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        let rect = convert(NSRect(x: x, y: y, width: width, height: height), to: nil)
        return window?.convertToScreen(rect) ?? rect
    }

    public override func doCommand(by selector: Selector) {}

    private func createSurfaceIfNeeded() {
        guard surface == nil, !surfaceClosed, let workingDirectory else { return }
        do { try GhosttyApp.shared.initialize() } catch { onEvent(.notification(title: "Terminal Error", body: error.localizedDescription)); return }
        guard let app = GhosttyApp.shared.app else { return }
        let bridge = GhosttySurfaceBridge { [weak self] event in self?.onEvent(event) }
        bridge.view = self
        let bridgePointer = Unmanaged.passUnretained(bridge).toOpaque()
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        config.userdata = bridgePointer
        config.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = 0
        config.context = GHOSTTY_SURFACE_CONTEXT_TAB
        let created = workingDirectory.path.withCString { path in
            config.working_directory = path
            if let startupInput, !startupInput.isEmpty {
                return startupInput.withCString { input in config.initial_input = input; return ghostty_surface_new(app, &config) }
            }
            return ghostty_surface_new(app, &config)
        }
        guard let created else { onEvent(.notification(title: "Terminal Error", body: GhosttyHostError.surfaceFailed.localizedDescription)); return }
        self.surface = created
        self.bridge = bridge
        self.bridgePointer = bridgePointer
        bridge.surface = created
        GhosttyApp.shared.register(surface: created, bridge: bridge)
        if let configuration = GhosttyApp.shared.configuration(scrollbackValue: scrollback.ghosttyConfigurationValue) {
            ghostty_surface_update_config(created, configuration)
            ghostty_config_free(configuration)
        }
        let tee = Unmanaged.passRetained(TerminalOutputObserver { [weak self] output in self?.onObservedOutput(output) })
        outputTee = tee
        ghostty_surface_set_pty_tee_cb(created, terminalOutputObserverCallback, tee.toOpaque())
        updateGeometry()
        updateVisibility()
        ghostty_surface_refresh(created)
    }

    private func updateGeometry() {
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)
        let size = convertToBacking(bounds).size
        ghostty_surface_set_size(surface, UInt32(max(1, size.width.rounded(.up))), UInt32(max(1, size.height.rounded(.up))))
        if let displayID = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber { ghostty_surface_set_display_id(surface, displayID.uint32Value) }
        ghostty_surface_refresh(surface)
    }

    private func updateVisibility() {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, window != nil && !isHidden && !isHiddenOrHasHiddenAncestor)
    }

    private func sendText(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        text.withCString { ghostty_surface_text_input(surface, $0, UInt(text.utf8.count)) }
    }

    private func sendCommittedText(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
    }

    private func sendMouse(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e,
        updatePosition: Bool
    ) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        if updatePosition { sendMousePosition(event) }
        _ = ghostty_surface_mouse_button(surface, state, button, ghosttyModifiers(event.modifierFlags))
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = TerminalInputMapping.ghosttyMousePosition(viewPoint: viewPoint, boundsHeight: bounds.height)
        // Raw out-of-bounds drag positions are intentional: Ghostty uses them
        // to drive selection auto-scroll beyond the visible viewport.
        ghostty_surface_mouse_pos(surface, point.x, point.y, ghosttyModifiers(event.modifierFlags))
    }

    private func ghosttyKey(_ event: NSEvent, action: ghostty_input_action_e) -> ghostty_input_key_s {
        let unshiftedCodepoint = TerminalInputMapping.unshiftedCodepoint(for: event.charactersIgnoringModifiers)
        let mods = ghosttyModifiers(event.modifierFlags)
        return ghostty_input_key_s(action: action, mods: mods, consumed_mods: GHOSTTY_MODS_NONE, keycode: ghosttyPhysicalKey(event.keyCode), text: nil, unshifted_codepoint: unshiftedCodepoint, composing: hasMarkedText())
    }

    private func ghosttyPhysicalKey(_ keyCode: UInt16) -> UInt32 {
        TerminalInputMapping.ghosttyKeyCode(for: keyCode)
    }

    private func ghosttyModifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        TerminalInputMapping.ghosttyModifiers(for: flags)
    }

    private func translatedKeyEvent(
        from event: NSEvent,
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSEvent {
        guard modifierFlags != event.modifierFlags else { return event }
        return NSEvent.keyEvent(
            with: event.type,
            location: event.locationInWindow,
            modifierFlags: modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: event.characters(byApplyingModifiers: modifierFlags) ?? event.characters ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) ?? event
    }

    private func mouseButton(_ number: Int) -> ghostty_input_mouse_button_e {
        switch number { case 2: return GHOSTTY_MOUSE_MIDDLE; case 3: return GHOSTTY_MOUSE_FOUR; case 4: return GHOSTTY_MOUSE_FIVE; default: return GHOSTTY_MOUSE_UNKNOWN }
    }

    private func updateCursorVisibility() {
        if isCursorHiddenByTerminal { NSCursor.hide() } else { NSCursor.unhide() }
    }
}

private final class TerminalOutputObserver {
    private let handler: @MainActor (String) -> Void
    init(handler: @escaping @MainActor (String) -> Void) { self.handler = handler }
    func receive(_ bytes: UnsafePointer<CChar>?, length: UInt) {
        guard let bytes, length > 0 else { return }
        let value = String(decoding: Data(bytes: bytes, count: Int(length)), as: UTF8.self)
        Task { @MainActor in handler(value) }
    }
}

private let terminalOutputObserverCallback: ghostty_pty_tee_cb = { userdata, bytes, length in
    guard let userdata else { return }
    Unmanaged<TerminalOutputObserver>.fromOpaque(userdata).takeUnretainedValue().receive(bytes, length: length)
}
#endif
