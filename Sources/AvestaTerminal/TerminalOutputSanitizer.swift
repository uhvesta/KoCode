import Foundation

public enum TerminalOutputSanitizer {
    public static func displayText(from output: String) -> String {
        var result = ""
        var index = output.startIndex

        while index < output.endIndex {
            let scalar = output[index]

            if scalar == "\u{001B}" {
                consumeEscapeSequence(in: output, index: &index)
                continue
            }

            if scalar == "\r" {
                result.append("\n")
                index = output.index(after: index)
                continue
            }

            if scalar.unicodeScalars.allSatisfy({ $0.value < 0x20 && $0.value != 0x0A && $0.value != 0x09 }) {
                index = output.index(after: index)
                continue
            }

            result.append(scalar)
            index = output.index(after: index)
        }

        return result
    }

    private static func consumeEscapeSequence(in output: String, index: inout String.Index) {
        index = output.index(after: index)
        guard index < output.endIndex else { return }

        let introducer = output[index]
        if introducer == "[" {
            consumeCSI(in: output, index: &index)
        } else if introducer == "]" {
            consumeOSC(in: output, index: &index)
        } else {
            index = output.index(after: index)
        }
    }

    private static func consumeCSI(in output: String, index: inout String.Index) {
        index = output.index(after: index)
        while index < output.endIndex {
            let value = output[index].unicodeScalars.first?.value ?? 0
            index = output.index(after: index)
            if value >= 0x40 && value <= 0x7E {
                break
            }
        }
    }

    private static func consumeOSC(in output: String, index: inout String.Index) {
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
