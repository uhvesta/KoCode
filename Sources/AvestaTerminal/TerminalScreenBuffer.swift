import Foundation

struct TerminalScreenBuffer {
    private var lines: [String] = [""]
    private var cursorRow = 0
    private var cursorColumn = 0
    private let maximumLines = 5_000

    var renderedText: String {
        lines.joined(separator: "\n")
    }

    mutating func write(_ output: String) {
        var index = output.startIndex

        while index < output.endIndex {
            let character = output[index]

            if character == "\u{001B}" {
                consumeEscapeSequence(in: output, index: &index)
                continue
            }

            switch character {
            case "\r":
                cursorColumn = 0
            case "\n":
                newline()
            case "\u{0008}", "\u{007F}":
                if cursorColumn > 0 {
                    cursorColumn -= 1
                    removeCharacter()
                }
            case "\t":
                let spaces = max(1, 8 - (cursorColumn % 8))
                for _ in 0..<spaces {
                    put(" ")
                }
            default:
                if character.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) {
                    put(character)
                }
            }

            index = output.index(after: index)
        }
    }

    private mutating func newline() {
        cursorRow += 1
        cursorColumn = 0
        if cursorRow >= lines.count {
            lines.append("")
        }
        trimIfNeeded()
    }

    private mutating func put(_ character: Character) {
        ensureCursor()
        var line = Array(lines[cursorRow])
        while line.count < cursorColumn {
            line.append(" ")
        }
        if cursorColumn < line.count {
            line[cursorColumn] = character
        } else {
            line.append(character)
        }
        lines[cursorRow] = String(line)
        cursorColumn += 1
    }

    private mutating func removeCharacter() {
        ensureCursor()
        var line = Array(lines[cursorRow])
        guard cursorColumn < line.count else { return }
        line.remove(at: cursorColumn)
        lines[cursorRow] = String(line)
    }

    private mutating func ensureCursor() {
        while cursorRow >= lines.count {
            lines.append("")
        }
    }

    private mutating func trimIfNeeded() {
        guard lines.count > maximumLines else { return }
        let overflow = lines.count - maximumLines
        lines.removeFirst(overflow)
        cursorRow = max(0, cursorRow - overflow)
    }

    private mutating func consumeEscapeSequence(in output: String, index: inout String.Index) {
        index = output.index(after: index)
        guard index < output.endIndex else { return }

        switch output[index] {
        case "[":
            consumeCSI(in: output, index: &index)
        case "]":
            consumeOSC(in: output, index: &index)
        default:
            index = output.index(after: index)
        }
    }

    private mutating func consumeCSI(in output: String, index: inout String.Index) {
        index = output.index(after: index)
        var parameters = ""

        while index < output.endIndex {
            let character = output[index]
            let value = character.unicodeScalars.first?.value ?? 0
            index = output.index(after: index)

            if value >= 0x40 && value <= 0x7E {
                applyCSI(final: character, parameters: parameters)
                break
            }

            parameters.append(character)
        }
    }

    private mutating func applyCSI(final: Character, parameters: String) {
        let values = parameters
            .split(separator: ";")
            .compactMap { Int($0) }
        let first = values.first ?? 1

        switch final {
        case "A":
            cursorRow = max(0, cursorRow - first)
        case "B":
            cursorRow += first
            ensureCursor()
        case "C":
            cursorColumn += first
        case "D":
            cursorColumn = max(0, cursorColumn - first)
        case "G":
            cursorColumn = max(0, first - 1)
        case "H", "f":
            cursorRow = max(0, (values.first ?? 1) - 1)
            cursorColumn = max(0, (values.dropFirst().first ?? 1) - 1)
            ensureCursor()
        case "J":
            if first == 2 || first == 3 || parameters.isEmpty {
                lines = [""]
                cursorRow = 0
                cursorColumn = 0
            }
        case "K":
            eraseLine(mode: values.first ?? 0)
        case "m", "h", "l", "r", "s", "u":
            break
        default:
            break
        }
    }

    private mutating func eraseLine(mode: Int) {
        ensureCursor()
        var line = Array(lines[cursorRow])

        switch mode {
        case 1:
            let end = min(cursorColumn, line.count)
            if end > 0 {
                line.replaceSubrange(0..<end, with: Array(repeating: " ", count: end))
            }
        case 2:
            line.removeAll()
        default:
            if cursorColumn < line.count {
                line.removeSubrange(cursorColumn..<line.count)
            }
        }

        lines[cursorRow] = String(line)
    }

    private mutating func consumeOSC(in output: String, index: inout String.Index) {
        index = output.index(after: index)
        while index < output.endIndex {
            if output[index] == "\u{0007}" {
                index = output.index(after: index)
                break
            }

            if output[index] == "\u{001B}" {
                let next = output.index(after: index)
                if next < output.endIndex, output[next] == "\\" {
                    index = output.index(after: next)
                    break
                }
            }

            index = output.index(after: index)
        }
    }
}
