#if os(macOS)
import AppKit
import Foundation
import GhosttyKit

public enum GhosttyRuntimeEvent: Sendable {
    case title(String)
    case workingDirectory(String)
    case notification(title: String, body: String)
    case commandFinished(exitCode: Int)
    case closeRequested
}

@MainActor
public final class GhosttyApp {
    public static let shared = GhosttyApp()

    public private(set) var app: ghostty_app_t?
    private var baseConfiguration: ghostty_config_t?
    private var initialized = false
    private var tickScheduled = false
    private var surfaceBridges: [UInt: GhosttySurfaceBridge] = [:]

    private init() {}

    public func initialize(applicationOverrides: String = "") throws {
        guard !initialized else { return }
        guard ghostty_init(0, nil) == GHOSTTY_SUCCESS else { throw GhosttyHostError.initializationFailed }
        guard let configuration = ghostty_config_new() else { throw GhosttyHostError.configurationFailed }
        ghostty_config_load_default_files(configuration)
        ghostty_config_load_recursive_files(configuration)
        if !applicationOverrides.isEmpty {
            applicationOverrides.withCString { pointer in
                "AvestaCode SQLite overrides".withCString { source in
                    ghostty_config_load_string(configuration, pointer, UInt(applicationOverrides.utf8.count), source)
                }
            }
        }
        ghostty_config_finalize(configuration)

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = ghosttyWakeupCallback
        runtime.action_cb = ghosttyActionCallback
        runtime.read_clipboard_cb = ghosttyReadClipboardCallback
        runtime.confirm_read_clipboard_cb = ghosttyConfirmClipboardCallback
        runtime.write_clipboard_cb = ghosttyWriteClipboardCallback
        runtime.close_surface_cb = ghosttyCloseSurfaceCallback
        guard let app = ghostty_app_new(&runtime, configuration) else {
            ghostty_config_free(configuration)
            throw GhosttyHostError.applicationFailed
        }
        self.app = app
        baseConfiguration = configuration
        initialized = true
        updateColorScheme()
    }

    public func configuration(scrollbackValue: String) -> ghostty_config_t? {
        guard let baseConfiguration, let copy = ghostty_config_clone(baseConfiguration) else { return nil }
        let line = "scrollback-limit = \(scrollbackValue)\n"
        line.withCString { pointer in
            "AvestaCode terminal override".withCString { source in
                ghostty_config_load_string(copy, pointer, UInt(line.utf8.count), source)
            }
        }
        ghostty_config_finalize(copy)
        return copy
    }

    public func register(surface: ghostty_surface_t, bridge: GhosttySurfaceBridge) {
        surfaceBridges[Self.key(surface)] = bridge
    }

    public func unregister(surface: ghostty_surface_t) {
        surfaceBridges[Self.key(surface)] = nil
    }

    public func bridge(for surface: ghostty_surface_t?) -> GhosttySurfaceBridge? {
        guard let surface else { return nil }
        return surfaceBridges[Self.key(surface)]
    }

    public func updateColorScheme() {
        guard let app else { return }
        ghostty_app_set_color_scheme(app, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
    }

    public func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tickScheduled = false
            if let app = self.app { ghostty_app_tick(app) }
        }
    }

    public func handle(action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE, let bridge = bridge(for: target.target.surface) else { return false }
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE, GHOSTTY_ACTION_SET_TAB_TITLE:
            if let pointer = action.action.set_title.title { bridge.emit(.title(String(cString: pointer))) }
            return true
        case GHOSTTY_ACTION_PWD:
            if let pointer = action.action.pwd.pwd { bridge.emit(.workingDirectory(String(cString: pointer))) }
            return true
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let title = action.action.desktop_notification.title.map(String.init(cString:)) ?? "Terminal"
            let body = action.action.desktop_notification.body.map(String.init(cString:)) ?? ""
            bridge.emit(.notification(title: title, body: body))
            return true
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            bridge.emit(.commandFinished(exitCode: Int(action.action.command_finished.exit_code)))
            return true
        case GHOSTTY_ACTION_RENDER:
            bridge.refresh()
            return true
        case GHOSTTY_ACTION_CLOSE_TAB, GHOSTTY_ACTION_CLOSE_WINDOW:
            bridge.emit(.closeRequested)
            return true
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            bridge.view?.isCursorHiddenByTerminal = action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN
            return true
        default:
            return false
        }
    }

    public func shutdown() {
        TerminalSurfaceRegistry.shared.releaseAll()
        surfaceBridges.removeAll()
        if let app { ghostty_app_free(app) }
        if let baseConfiguration { ghostty_config_free(baseConfiguration) }
        app = nil
        baseConfiguration = nil
        initialized = false
    }

    private static func key(_ surface: ghostty_surface_t) -> UInt { UInt(bitPattern: surface) }
}

public final class GhosttySurfaceBridge: @unchecked Sendable {
    public weak var view: TerminalMetalView?
    public var surface: ghostty_surface_t?
    private let eventHandler: @MainActor (GhosttyRuntimeEvent) -> Void

    public init(eventHandler: @escaping @MainActor (GhosttyRuntimeEvent) -> Void) { self.eventHandler = eventHandler }

    public func emit(_ event: GhosttyRuntimeEvent) { Task { @MainActor in eventHandler(event) } }
    public func refresh() { Task { @MainActor [weak self] in self?.view?.refreshSurface() } }
}

public enum GhosttyHostError: Error, LocalizedError {
    case initializationFailed, configurationFailed, applicationFailed, surfaceFailed
    public var errorDescription: String? {
        switch self {
        case .initializationFailed: return "libghostty initialization failed"
        case .configurationFailed: return "Ghostty configuration creation failed"
        case .applicationFailed: return "Ghostty application creation failed"
        case .surfaceFailed: return "Ghostty terminal surface creation failed"
        }
    }
}

private let ghosttyWakeupCallback: ghostty_runtime_wakeup_cb = { userdata in
    guard let userdata else { return }
    let host = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in host.scheduleTick() }
}

private let ghosttyActionCallback: ghostty_runtime_action_cb = { app, target, action in
    guard let userdata = ghostty_app_userdata(app) else { return false }
    let host = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
    return MainActor.assumeIsolated { host.handle(action: action, target: target) }
}

private let ghosttyReadClipboardCallback: ghostty_runtime_read_clipboard_cb = { userdata, _, state in
    guard let userdata else { return false }
    let bridge = Unmanaged<GhosttySurfaceBridge>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        guard let surface = bridge.surface else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        text.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
    }
    return true
}

private let ghosttyConfirmClipboardCallback: ghostty_runtime_confirm_read_clipboard_cb = { userdata, text, state, _ in
    guard let userdata else { return }
    let bridge = Unmanaged<GhosttySurfaceBridge>.fromOpaque(userdata).takeUnretainedValue()
    Task { @MainActor in
        guard let surface = bridge.surface else { return }
        ghostty_surface_complete_clipboard_request(surface, text, state, false)
    }
}

private let ghosttyWriteClipboardCallback: ghostty_runtime_write_clipboard_cb = { _, _, content, count, _ in
    guard let content, count > 0 else { return }
    var value = ""
    for index in 0..<count where content[Int(index)].mime.map({ String(cString: $0) == "text/plain" }) == true {
        if let pointer = content[Int(index)].data { value = String(cString: pointer); break }
    }
    Task { @MainActor in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private let ghosttyCloseSurfaceCallback: ghostty_runtime_close_surface_cb = { userdata, _ in
    guard let userdata else { return }
    Unmanaged<GhosttySurfaceBridge>.fromOpaque(userdata).takeUnretainedValue().emit(.closeRequested)
}
#endif
