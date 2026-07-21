#if os(macOS)
import AppKit
import XCTest
@testable import AvestaTerminal

/// These tests use the actual libghostty app/surface and PTY. They are opt-in
/// because a normal XCTest process may not have a WindowServer connection.
/// Run them locally with:
///
///     AVESTACODE_RUN_GHOSTTY_E2E=1 swift test --filter GhosttySurfaceE2ETests
@MainActor
final class GhosttySurfaceE2ETests: XCTestCase {
    func testSpecialKeysReachTheGhosttyOwnedPTY() throws {
        try requireOptIn()

        let workspace = FileManager.default.temporaryDirectory
            .appending(path: "avestacode-ghostty-input-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        var output = ""
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        NSApplication.shared.activate(ignoringOtherApps: true)
        let view = TerminalMetalView(tabID: UUID())
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer {
            view.closeSurface()
            window.orderOut(nil)
            GhosttyApp.shared.shutdown()
        }

        // raw mode makes the shell's foreground tty report exactly what the
        // Ghostty input API wrote. `od` prints that byte stream, then exits.
        // A newline is included because initial_input is injected directly
        // into the shell's PTY by libghostty (it is not an AppKit key event).
        let command = "stty raw -echo; printf '\\x41\\x56\\x45\\x53\\x54\\x41_READY'; dd bs=1 count=10 2>/dev/null | od -An -t x1; stty sane; sh -c 'trap \"printf AVE%s_SIGINT STA; exit 0\" INT; printf AVE%s_CTRL_READY STA; while :; do read line; done'; exit\n"
        view.configureSurface(
            workingDirectory: workspace,
            startupInput: command,
            scrollback: .limited(lines: 1_000),
            onFocus: {},
            onEvent: { _ in },
            onObservedOutput: { output += $0 }
        )
        XCTAssertTrue(window.makeFirstResponder(view))
        pumpMainRunLoop(until: { view.hasLiveSurface }, timeout: 5)
        XCTAssertTrue(view.hasLiveSurface, "the real libghostty surface did not start")
        window.makeKey()
        _ = view.becomeFirstResponder()
        pumpMainRunLoop(until: { false }, timeout: 0.5)

        pumpMainRunLoop(until: { output.contains("AVESTA_READY") }, timeout: 5)
        XCTAssertTrue(output.contains("AVESTA_READY"), "probe command was not executed")

        // In raw mode the real Ghostty-owned PTY must receive the exact
        // sequences Ghostty encodes for Backspace, forward Delete, Left,
        // Return, and Tab.
        _ = sendKey(to: view, keyCode: 0x33, characters: "\u{8}", charactersIgnoringModifiers: "\u{8}")
        _ = sendKey(to: view, keyCode: 0x75, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}")
        _ = sendKey(to: view, keyCode: 0x7B, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}")
        _ = sendKey(to: view, keyCode: 0x24, characters: "\r", charactersIgnoringModifiers: "\r")
        _ = sendKey(to: view, keyCode: 0x30, characters: "\t", charactersIgnoringModifiers: "\t")

        let expectedBytes = "7f 1b 5b 33 7e 1b 5b 44 0d 09"
        let normalizedOutput = { output.split(whereSeparator: \Character.isWhitespace).joined(separator: " ") }
        pumpMainRunLoop(until: { normalizedOutput().contains(expectedBytes) }, timeout: 5)
        XCTAssertTrue(
            normalizedOutput().contains(expectedBytes),
            "unexpected bytes from Ghostty-owned PTY: \(output.debugDescription)"
        )

        // Ctrl-C is terminal input semantics, not paste data. In canonical
        // mode it must interrupt the foreground process through Ghostty and
        // the PTY rather than merely being captured as another dd byte.
        pumpMainRunLoop(until: { output.contains("AVESTA_CTRL_READY") }, timeout: 5)
        XCTAssertTrue(output.contains("AVESTA_CTRL_READY"), "SIGINT probe did not start")
        _ = sendKey(to: view, keyCode: 0x08, modifiers: .control, characters: "\u{3}", charactersIgnoringModifiers: "c")
        pumpMainRunLoop(until: { output.contains("AVESTA_SIGINT") }, timeout: 5)
        XCTAssertTrue(
            output.contains("AVESTA_SIGINT"),
            "Ctrl-C did not interrupt the foreground process: \(output.debugDescription)"
        )

        // Exercise the remaining non-character and shortcut-conflict matrix
        // through AppKit. The exact byte assertion above is the regression
        // check for the keys that previously arrived as spaces/wrong ASCII.
        let navigationMatrix: [(UInt16, String, String)] = [
            (0x7C, "\u{F703}", "\u{F703}"), (0x7D, "\u{F701}", "\u{F701}"), (0x7E, "\u{F700}", "\u{F700}"),
            (0x73, "\u{F729}", "\u{F729}"), (0x77, "\u{F72B}", "\u{F72B}"), (0x74, "\u{F72C}", "\u{F72C}"),
            (0x79, "\u{F72D}", "\u{F72D}"), (0x35, "\u{1B}", "\u{1B}"), (0x4C, "\r", "\r"),
            (0x7A, "", ""), (0x78, "", ""), (0x63, "", ""), (0x76, "", ""), (0x60, "", ""),
            (0x61, "", ""), (0x62, "", ""), (0x64, "", ""), (0x65, "", ""), (0x6D, "", ""), (0x67, "", ""), (0x6F, "", "")
        ]
        for (keyCode, characters, ignored) in navigationMatrix {
            _ = sendKey(to: view, keyCode: keyCode, characters: characters, charactersIgnoringModifiers: ignored)
        }
        _ = sendKey(to: view, keyCode: 0x18, modifiers: [.command, .shift], characters: "+", charactersIgnoringModifiers: "=")
        _ = sendKey(to: view, keyCode: 0x1B, modifiers: .command, characters: "-", charactersIgnoringModifiers: "-")
        _ = sendKey(to: view, keyCode: 0x09, modifiers: .command, characters: "v", charactersIgnoringModifiers: "v")

        pumpMainRunLoop(until: { false }, timeout: 0.2)
    }

    private func requireOptIn() throws {
        guard ProcessInfo.processInfo.environment["AVESTACODE_RUN_GHOSTTY_E2E"] == "1" else {
            throw XCTSkip("set AVESTACODE_RUN_GHOSTTY_E2E=1 to run the WindowServer/libghostty PTY test")
        }
    }

    @discardableResult
    private func sendKey(
        to view: TerminalMetalView,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String,
        charactersIgnoringModifiers: String
    ) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )!
        // Route through AppKit's normal responder dispatch, just as a real
        // keyboard event does; this also exercises first-responder focus.
        view.window?.sendEvent(event)
        if let keyUp = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ) {
            view.window?.sendEvent(keyUp)
        }
        return true
    }

    private func pumpMainRunLoop(until condition: @escaping () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

}
#endif
