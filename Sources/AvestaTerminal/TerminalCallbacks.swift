import Foundation

public enum TerminalCallbacks {
    public static func handleWrite(_ text: String, onOutput: (String) -> Void) {
        onOutput(text)
    }
}
