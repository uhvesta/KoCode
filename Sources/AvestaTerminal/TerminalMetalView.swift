#if os(macOS)
import AppKit
import Carbon.HIToolbox
import GhosttyKit
import QuartzCore

public final class TerminalMetalView: NSView {
    private var surface: ghostty_surface_t?
    private var onOutput: ((String) -> Void)?
    private var onExit: (() -> Void)?
    private var outputTee: Unmanaged<TerminalOutputTee>?
    private var workingDirectory: URL?
    private var startupInput: String?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    deinit {
        stop()
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.backgroundColor = NSColor.textBackgroundColor.cgColor
        return layer
    }

    public func createSurface(
        workingDirectory: URL,
        startupInput: String? = nil,
        onOutput: @escaping (String) -> Void,
        onExit: @escaping () -> Void
    ) {
        self.workingDirectory = preparedWorkingDirectory(workingDirectory)
        self.startupInput = startupInput
        self.onOutput = onOutput
        self.onExit = onExit
        GhosttyApp.shared.initialize()
        guard surface == nil else { return }
        createNativeSurfaceIfNeeded()
    }

    public func paste(_ text: String) {
        sendText(text)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        createNativeSurfaceIfNeeded()
        updateSurfaceGeometry()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceGeometry()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceGeometry()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        if let surface {
            ghostty_surface_set_occlusion(surface, false)
        }
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        if let surface {
            ghostty_surface_set_occlusion(surface, true)
            ghostty_surface_refresh(surface)
        }
    }

    public override func becomeFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return true
    }

    public override func resignFirstResponder() -> Bool {
        if let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        guard let surface, !event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }

        ghostty_surface_set_focus(surface, true)

        let translationMods = ghostty_surface_key_translation_mods(surface, ghosttyModifiers(from: event.modifierFlags))
        let translatedFlags = translationModifierFlags(original: event.modifierFlags, ghosttyTranslationMods: translationMods)
        let translatedEvent = translatedKeyEvent(from: event, modifierFlags: translatedFlags)

        var keyEvent = keyEvent(for: event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
        keyEvent.consumed_mods = consumedModifiers(from: translatedFlags)
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: translatedEvent)

        if let text = textForKeyEvent(translatedEvent), shouldSendText(text) {
            text.withCString { pointer in
                keyEvent.text = pointer
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard let surface else {
            super.keyUp(with: event)
            return
        }

        var keyEvent = keyEvent(for: event, action: GHOSTTY_ACTION_RELEASE)
        keyEvent.text = nil
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    public override func flagsChanged(with event: NSEvent) {
        guard let surface else {
            super.flagsChanged(with: event)
            return
        }

        guard let action = modifierActionForFlagsChanged(keyCode: event.keyCode, modifierFlagsRawValue: event.modifierFlags.rawValue) else {
            super.flagsChanged(with: event)
            return
        }

        var keyEvent = keyEvent(for: event, action: action)
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, keyEvent)
    }

    private func configureView() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    private func createNativeSurfaceIfNeeded() {
        guard surface == nil,
              let app = GhosttyApp.shared.app,
              let workingDirectory else { return }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        config.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = 13
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let created = workingDirectory.path.withCString { pathPointer in
            config.working_directory = pathPointer
            if let startupInput, !startupInput.isEmpty {
                return startupInput.withCString { inputPointer in
                    config.initial_input = inputPointer
                    return ghostty_surface_new(app, &config)
                }
            }
            return ghostty_surface_new(app, &config)
        }

        guard let created else {
            appendHostMessage("Failed to create terminal surface.\n")
            return
        }

        surface = created
        let tee = Unmanaged.passRetained(TerminalOutputTee(onOutput: { [weak self] output in
            self?.onOutput?(output)
        }))
        outputTee = tee
        ghostty_surface_set_pty_tee_cb(created, terminalOutputTeeCallback, tee.toOpaque())
        updateSurfaceGeometry()
        ghostty_surface_set_focus(created, window?.firstResponder === self)
        ghostty_surface_set_occlusion(created, !isHidden)
        ghostty_surface_refresh(created)
    }

    private func preparedWorkingDirectory(_ directory: URL) -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            let fallback = FileManager.default.homeDirectoryForCurrentUser
            appendHostMessage("Could not create terminal directory \(directory.path): \(error.localizedDescription)\nUsing \(fallback.path).\n")
            return fallback
        }
    }

    private func stop() {
        if let surface {
            ghostty_surface_set_pty_tee_cb(surface, nil, nil)
            ghostty_surface_free(surface)
        }
        surface = nil
        outputTee?.release()
        outputTee = nil
    }

    private func updateSurfaceGeometry() {
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)
        let backingSize = convertToBacking(bounds).size
        ghostty_surface_set_size(
            surface,
            UInt32(max(1, backingSize.width.rounded(.up))),
            UInt32(max(1, backingSize.height.rounded(.up)))
        )
        ghostty_surface_refresh(surface)
    }

    private func sendText(_ text: String) {
        guard let surface else { return }
        text.withCString { pointer in
            ghostty_surface_text_input(surface, pointer, UInt(text.utf8.count))
        }
    }

    private func keyEvent(for event: NSEvent, action: ghostty_input_action_e) -> ghostty_input_key_s {
        ghostty_input_key_s(
            action: action,
            mods: ghosttyModifiers(from: event.modifierFlags),
            consumed_mods: GHOSTTY_MODS_NONE,
            keycode: UInt32(event.keyCode),
            text: nil,
            unshifted_codepoint: unshiftedCodepoint(from: event),
            composing: false
        )
    }

    private func ghosttyModifiers(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) {
            raw |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if flags.contains(.control) {
            raw |= GHOSTTY_MODS_CTRL.rawValue
        }
        if flags.contains(.option) {
            raw |= GHOSTTY_MODS_ALT.rawValue
        }
        if flags.contains(.command) {
            raw |= GHOSTTY_MODS_SUPER.rawValue
        }
        if flags.contains(.capsLock) {
            raw |= GHOSTTY_MODS_CAPS.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_CTRL_RIGHT.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_ALT_RIGHT.rawValue
        }
        if flags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0 {
            raw |= GHOSTTY_MODS_SUPER_RIGHT.rawValue
        }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func consumedModifiers(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) {
            raw |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if flags.contains(.option) {
            raw |= GHOSTTY_MODS_ALT.rawValue
        }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func translationModifierFlags(
        original flags: NSEvent.ModifierFlags,
        ghosttyTranslationMods: ghostty_input_mods_e
    ) -> NSEvent.ModifierFlags {
        var translated = flags
        let pairs: [(NSEvent.ModifierFlags, ghostty_input_mods_e)] = [
            (.shift, GHOSTTY_MODS_SHIFT),
            (.control, GHOSTTY_MODS_CTRL),
            (.option, GHOSTTY_MODS_ALT),
            (.command, GHOSTTY_MODS_SUPER)
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

    private func translatedKeyEvent(from event: NSEvent, modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
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

    private func textForKeyEvent(_ event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty else { return nil }

        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if isControlCharacter(scalar) {
                if flags.contains(.control) {
                    return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
                }

                if scalar.value == 0x1B,
                   flags == [.shift],
                   event.charactersIgnoringModifiers == "`" {
                    return "~"
                }
            }

            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    private func shouldSendText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.count == 1, let scalar = text.unicodeScalars.first {
            return !isControlCharacter(scalar)
        }
        return true
    }

    private func isControlCharacter(_ scalar: UnicodeScalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F
    }

    private func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        guard let characters = event.charactersIgnoringModifiers ?? event.characters,
              let scalar = characters.unicodeScalars.first,
              scalar.value >= 0x20,
              !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF) else {
            return 0
        }
        return scalar.value
    }

    private func modifierActionForFlagsChanged(
        keyCode: UInt16,
        modifierFlagsRawValue rawValue: UInt
    ) -> ghostty_input_action_e? {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        let modifierActive: Bool
        switch keyCode {
        case 0x39:
            modifierActive = flags.contains(.capsLock)
        case 0x38, 0x3C:
            modifierActive = flags.contains(.shift)
        case 0x3B, 0x3E:
            modifierActive = flags.contains(.control)
        case 0x3A, 0x3D:
            modifierActive = flags.contains(.option)
        case 0x37, 0x36:
            modifierActive = flags.contains(.command)
        default:
            return nil
        }

        guard modifierActive else { return GHOSTTY_ACTION_RELEASE }

        let sidePressed: Bool
        switch keyCode {
        case 0x38:
            sidePressed = rawValue & UInt(NX_DEVICELSHIFTKEYMASK) != 0
        case 0x3C:
            sidePressed = rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
        case 0x3B:
            sidePressed = rawValue & UInt(NX_DEVICELCTLKEYMASK) != 0
        case 0x3E:
            sidePressed = rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
        case 0x3A:
            sidePressed = rawValue & UInt(NX_DEVICELALTKEYMASK) != 0
        case 0x3D:
            sidePressed = rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
        case 0x37:
            sidePressed = rawValue & UInt(NX_DEVICELCMDKEYMASK) != 0
        case 0x36:
            sidePressed = rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
        default:
            sidePressed = true
        }

        return sidePressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    }

    private func appendHostMessage(_ message: String) {
        onOutput?(message)
    }
}

private final class TerminalOutputTee {
    private let onOutput: (String) -> Void

    init(onOutput: @escaping (String) -> Void) {
        self.onOutput = onOutput
    }

    func handle(bytes: UnsafePointer<CChar>?, length: UInt) {
        guard let bytes, length > 0 else { return }
        let data = Data(bytes: bytes, count: Int(length))
        let output = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        DispatchQueue.main.async { [onOutput] in
            onOutput(output)
        }
    }
}

private let terminalOutputTeeCallback: ghostty_pty_tee_cb = { userdata, bytes, length in
    guard let userdata else { return }
    Unmanaged<TerminalOutputTee>.fromOpaque(userdata).takeUnretainedValue().handle(bytes: bytes, length: length)
}
#endif
