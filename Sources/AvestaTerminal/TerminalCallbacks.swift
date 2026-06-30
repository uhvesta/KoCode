import Foundation
#if os(macOS)
import AppKit
#endif

public enum TerminalCallbacks {
    public static func wakeup(_ redraw: @escaping () -> Void) {
        DispatchQueue.main.async(execute: redraw)
    }

    public static func action(_ action: String, handler: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            handler(action)
        }
    }

    public static func clipboardRead() -> String {
        #if os(macOS)
        return NSPasteboard.general.string(forType: .string) ?? ""
        #else
        return ""
        #endif
    }

    public static func clipboardWrite(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    public static func closeSurface(_ close: @escaping () -> Void) {
        DispatchQueue.main.async(execute: close)
    }

    public static func handleWrite(_ text: String, onOutput: (String) -> Void) {
        onOutput(text)
    }
}
