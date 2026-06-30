import Foundation

public enum TerminalAgentKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case copilot
}

public struct TerminalAgentResumeSupport: Sendable {
    public var copilotResumeTemplate: String?

    public init(copilotResumeTemplate: String? = nil) {
        self.copilotResumeTemplate = copilotResumeTemplate
    }

    public func sessionID(from arguments: [String], agent: TerminalAgentKind) -> String? {
        switch agent {
        case .claude:
            return value(after: "--session-id", in: arguments)
                ?? value(after: "--resume", in: arguments)
                ?? value(after: "-r", in: arguments)
        case .codex:
            guard let resumeIndex = arguments.firstIndex(of: "resume") else { return nil }
            let nextIndex = arguments.index(after: resumeIndex)
            guard nextIndex < arguments.endIndex else { return nil }
            return normalized(arguments[nextIndex])
        case .copilot:
            return value(after: "--session-id", in: arguments)
                ?? value(after: "--resume", in: arguments)
                ?? value(after: "-r", in: arguments)
                ?? value(after: "--conversation", in: arguments)
        }
    }

    public func resumeCommand(agent: TerminalAgentKind, sessionID: String) -> String? {
        let quoted = shellQuote(sessionID)
        switch agent {
        case .claude:
            return "claude --resume \(quoted)"
        case .codex:
            return "codex resume \(quoted)"
        case .copilot:
            if let copilotResumeTemplate, !copilotResumeTemplate.isEmpty {
                return copilotResumeTemplate.replacingOccurrences(of: "{{sessionId}}", with: quoted)
            }
            return "copilot --resume \(quoted)"
        }
    }

    public func resumeSnapshot(
        agent: TerminalAgentKind,
        sessionID: String,
        workingDirectory: URL?
    ) -> TerminalResumeSnapshot? {
        guard let command = resumeCommand(agent: agent, sessionID: sessionID) else { return nil }
        return TerminalResumeSnapshot(
            agent: agent.rawValue,
            sessionID: sessionID,
            command: command,
            workingDirectory: workingDirectory
        )
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        for index in arguments.indices {
            let argument = arguments[index]
            if argument == option {
                let nextIndex = arguments.index(after: index)
                guard nextIndex < arguments.endIndex else { return nil }
                return normalized(arguments[nextIndex])
            }

            let prefix = option + "="
            if argument.hasPrefix(prefix) {
                return normalized(String(argument.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("-") ? nil : trimmed
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
