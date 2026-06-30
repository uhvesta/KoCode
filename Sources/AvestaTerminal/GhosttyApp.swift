import Foundation

@MainActor
public final class GhosttyApp {
    public static let shared = GhosttyApp()

    public private(set) var isInitialized = false

    private init() {}

    public func initialize() {
        isInitialized = true
    }

    public func shutdown() {
        isInitialized = false
    }
}
