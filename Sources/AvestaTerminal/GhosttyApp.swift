import Foundation
import GhosttyKit

@MainActor
public final class GhosttyApp {
    public static let shared = GhosttyApp()

    public private(set) var app: ghostty_app_t?
    public private(set) var isInitialized = false
    private var config: ghostty_config_t?
    private var tickScheduled = false

    private init() {}

    public func initialize() {
        guard !isInitialized else { return }
        _ = ghostty_init(0, nil)
        let config = ghostty_config_new()
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = false
        runtimeConfig.wakeup_cb = { userdata in
            guard let userdata else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
            Task { @MainActor in
                app.scheduleTick()
            }
        }
        runtimeConfig.action_cb = { _, _, _ in false }
        runtimeConfig.close_surface_cb = { _, _ in }

        app = ghostty_app_new(&runtimeConfig, config)
        self.config = config
        isInitialized = true
    }

    public func shutdown() {
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
        app = nil
        config = nil
        isInitialized = false
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tickScheduled = false
            if let app = self.app {
                ghostty_app_tick(app)
            }
        }
    }
}
