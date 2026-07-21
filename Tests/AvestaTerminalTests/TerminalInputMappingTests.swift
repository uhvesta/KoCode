#if os(macOS)
import AppKit
import Carbon.HIToolbox
import GhosttyKit
import XCTest
@testable import AvestaTerminal

final class TerminalInputMappingTests: XCTestCase {
    func testNonCharacterKeysUseGhosttyKeyTextWhenAvailable() {
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: [], characters: "\r", charactersIgnoringModifiers: "\r"),
        )
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: [], characters: "\t", charactersIgnoringModifiers: "\t"),
        )
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: [], characters: "\u{8}", charactersIgnoringModifiers: "\u{8}"),
        )
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: [], characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}"),
        )
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: [], characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}"),
        )
    }

    func testControlKeysUsePrintableTextAndControlModifier() {
        // AppKit may expose Ctrl-C as either "\u{3}" or "c" in `characters`.
        // The Ghostty key event must carry "c" and GHOSTTY_MODS_CTRL, never a
        // raw control byte through ghostty_surface_text (which is plain text).
        XCTAssertEqual(
            TerminalInputMapping.text(modifiers: .control, characters: "\u{3}", charactersIgnoringModifiers: "c"),
            "c"
        )
        XCTAssertEqual(
            TerminalInputMapping.text(modifiers: .control, characters: "\u{4}", charactersIgnoringModifiers: "d"),
            "d"
        )
        XCTAssertEqual(
            TerminalInputMapping.text(modifiers: .control, characters: "\u{1A}", charactersIgnoringModifiers: "z"),
            "z"
        )
        XCTAssertEqual(
            TerminalInputMapping.text(modifiers: [.control, .shift], characters: "\u{3}", charactersIgnoringModifiers: "C"),
            "C"
        )

        let controlLetters = Array("abcdefghijklmnopqrstuvwxyz".unicodeScalars)
        for letter in controlLetters {
            XCTAssertEqual(
                TerminalInputMapping.text(
                    modifiers: .control,
                    characters: String(UnicodeScalar(letter.value & 0x1F)!),
                    charactersIgnoringModifiers: String(letter)
                ),
                String(letter),
                "Ctrl-\(letter) must keep printable text for Ghostty's key API"
            )
        }

        for value in ["[", "\\", "]", "^", "_", "?", " "] {
            XCTAssertEqual(
                TerminalInputMapping.text(modifiers: .control, characters: value, charactersIgnoringModifiers: value),
                value,
                "Ctrl-\(value) must remain a key event"
            )
        }
    }

    func testNavigationAndCommandShortcutsRemainPhysicalKeys() {
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: [], characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}")
        )
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: .command, characters: "=", charactersIgnoringModifiers: "=")
        )
        XCTAssertNil(
            TerminalInputMapping.text(modifiers: .command, characters: "v", charactersIgnoringModifiers: "v")
        )
    }

    func testPhysicalSpecialKeysAreNotCollapsedIntoCharacterKeys() {
        let enter = TerminalInputMapping.ghosttyKeyCode(for: 0x24)
        let keypadEnter = TerminalInputMapping.ghosttyKeyCode(for: 0x4C)
        let backspace = TerminalInputMapping.ghosttyKeyCode(for: 0x33)
        let forwardDelete = TerminalInputMapping.ghosttyKeyCode(for: 0x75)
        let left = TerminalInputMapping.ghosttyKeyCode(for: 0x7B)
        let right = TerminalInputMapping.ghosttyKeyCode(for: 0x7C)

        XCTAssertNotEqual(enter, keypadEnter)
        XCTAssertNotEqual(backspace, forwardDelete)
        XCTAssertNotEqual(left, right)
        XCTAssertEqual(
            Set([enter, keypadEnter, backspace, forwardDelete, left, right]).count,
            6,
            "every special key must retain its own macOS virtual keycode"
        )
        XCTAssertEqual(enter, 0x24)
        XCTAssertEqual(keypadEnter, 0x4C)
        XCTAssertEqual(backspace, 0x33)
        XCTAssertEqual(forwardDelete, 0x75)
        XCTAssertEqual(left, 0x7B)
        XCTAssertEqual(right, 0x7C)
    }

    func testCommandShortcutsNeverFallThroughToPlainText() {
        let shortcuts: [(NSEvent.ModifierFlags, String)] = [
            (.command, "c"), (.command, "v"), (.command, "x"),
            (.command, "+"), (.command, "-"), (.command, "="),
            ([.command, .shift], "z"), ([.command, .control], "c")
        ]
        for (modifiers, value) in shortcuts {
            XCTAssertNil(
                TerminalInputMapping.text(modifiers: modifiers, characters: value, charactersIgnoringModifiers: value),
                "\(modifiers) + \(value) must be delivered as a physical/modifier key event"
            )
        }
    }

    func testWorkspaceShortcutsAreReservedForApplicationMenu() {
        let shortcuts: [(NSEvent.ModifierFlags, String)] = [
            (.command, "t"), (.command, "w"), (.command, "1"), (.command, "9"),
            ([.command, .shift], "["), ([.command, .shift], "]"),
            ([.command, .option], "t"), ([.command, .shift], "r"),
        ]
        for (modifiers, key) in shortcuts {
            XCTAssertTrue(
                TerminalInputMapping.isWorkspaceShortcut(
                    modifiers: modifiers,
                    charactersIgnoringModifiers: key
                ),
                "\(modifiers) + \(key) must reach the application menu"
            )
        }

        XCTAssertFalse(
            TerminalInputMapping.isWorkspaceShortcut(
                modifiers: .command,
                charactersIgnoringModifiers: "c"
            ),
            "terminal copy remains a Ghostty shortcut"
        )
        XCTAssertFalse(
            TerminalInputMapping.isWorkspaceShortcut(
                modifiers: [.control, .shift],
                charactersIgnoringModifiers: "]"
            )
        )
    }

    func testOptionTextRemainsAvailableForCompositionOrAltTranslation() {
        XCTAssertEqual(
            TerminalInputMapping.text(
                modifiers: .option,
                characters: "…",
                charactersIgnoringModifiers: ";"
            ),
            "…"
        )
        XCTAssertNil(
            TerminalInputMapping.text(
                modifiers: .option,
                characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}"
            )
        )
    }

    func testSidedModifiersArePreservedForGhosttyConfiguration() {
        let rightOption = NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.option.rawValue | UInt(NX_DEVICERALTKEYMASK)
        )
        let mods = TerminalInputMapping.ghosttyModifiers(for: rightOption)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_ALT.rawValue, 0)
        XCTAssertNotEqual(mods.rawValue & GHOSTTY_MODS_ALT_RIGHT.rawValue, 0)

        let leftOption = TerminalInputMapping.ghosttyModifiers(for: .option)
        XCTAssertNotEqual(leftOption.rawValue & GHOSTTY_MODS_ALT.rawValue, 0)
        XCTAssertEqual(leftOption.rawValue & GHOSTTY_MODS_ALT_RIGHT.rawValue, 0)
    }

    func testOnlyTextTranslationModifiersAreMarkedConsumed() {
        let consumed = TerminalInputMapping.consumedModifiers(
            from: [.shift, .option, .control, .command]
        )
        XCTAssertNotEqual(consumed.rawValue & GHOSTTY_MODS_SHIFT.rawValue, 0)
        XCTAssertNotEqual(consumed.rawValue & GHOSTTY_MODS_ALT.rawValue, 0)
        XCTAssertEqual(consumed.rawValue & GHOSTTY_MODS_CTRL.rawValue, 0)
        XCTAssertEqual(consumed.rawValue & GHOSTTY_MODS_SUPER.rawValue, 0)
    }

    func testGhosttyTranslationControlsWhetherOptionComposesText() {
        let stripped = TerminalInputMapping.translationModifierFlags(
            original: [.option, .numericPad],
            ghosttyTranslationMods: GHOSTTY_MODS_NONE
        )
        XCTAssertFalse(stripped.contains(.option))
        XCTAssertTrue(stripped.contains(.numericPad))

        let retained = TerminalInputMapping.translationModifierFlags(
            original: [.option],
            ghosttyTranslationMods: GHOSTTY_MODS_ALT
        )
        XCTAssertTrue(retained.contains(.option))
    }

    func testModifierPressAndReleaseTracksPhysicalSide() {
        let rightShiftDown = NSEvent.ModifierFlags.shift.rawValue | UInt(NX_DEVICERSHIFTKEYMASK)
        XCTAssertEqual(
            TerminalInputMapping.modifierAction(keyCode: 0x3C, modifierFlagsRawValue: rightShiftDown),
            GHOSTTY_ACTION_PRESS
        )
        XCTAssertEqual(
            TerminalInputMapping.modifierAction(keyCode: 0x38, modifierFlagsRawValue: rightShiftDown),
            GHOSTTY_ACTION_RELEASE,
            "left Shift release must not be mistaken for a press because right Shift remains held"
        )
        XCTAssertEqual(
            TerminalInputMapping.modifierAction(keyCode: 0x3C, modifierFlagsRawValue: 0),
            GHOSTTY_ACTION_RELEASE
        )
        XCTAssertNil(TerminalInputMapping.modifierAction(keyCode: 0x24, modifierFlagsRawValue: 0))
    }

    func testAllAppKitNavigationKeyCodesHaveDistinctGhosttyCodes() {
        let appKitCodes: [UInt16] = [
            0x24, 0x4C, 0x30, 0x33, 0x75, 0x35,
            0x73, 0x77, 0x74, 0x79, 0x7B, 0x7C, 0x7D, 0x7E,
            0x41, 0x43, 0x45, 0x47, 0x4B, 0x4E, 0x51,
            0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C,
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x72
        ]
        let ghosttyCodes = appKitCodes.map(TerminalInputMapping.ghosttyKeyCode(for:))
        XCTAssertEqual(Set(ghosttyCodes).count, ghosttyCodes.count)
        XCTAssertEqual(ghosttyCodes, appKitCodes.map(UInt32.init))
    }

    func testEveryMacVirtualKeyCodeIsPassedThroughWithoutEnumTranslation() {
        for keyCode in UInt16(0)...UInt16(127) {
            XCTAssertEqual(
                TerminalInputMapping.ghosttyKeyCode(for: keyCode),
                UInt32(keyCode),
                "macOS virtual keycode \(keyCode) must remain in the platform keycode namespace"
            )
        }
    }

    func testNonPrintingKeysDoNotCarryASecondUnicodeSignal() {
        for value in ["\r", "\n", "\t", "\u{8}", "\u{7F}", "\u{1B}", "\u{F702}"] {
            XCTAssertEqual(
                TerminalInputMapping.unshiftedCodepoint(for: value),
                0,
                "\(value.debugDescription) must be represented by its physical Ghostty keycode"
            )
        }
        XCTAssertEqual(TerminalInputMapping.unshiftedCodepoint(for: "c"), 99)
        XCTAssertEqual(TerminalInputMapping.unshiftedCodepoint(for: "A"), 65)
    }
}
#endif
