import Foundation

public enum TerminalAgentEventKind: String, Codable, Sendable {
    case done
    case needsInput
    case error
}

public struct TerminalAgentEvent: Equatable, Sendable {
    public var kind: TerminalAgentEventKind
    public var title: String
    public var body: String

    public init(kind: TerminalAgentEventKind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

public struct TerminalAgentEventClassifier: Sendable {
    public init() {}

    public func event(from output: String) -> TerminalAgentEvent? {
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if let structured = structuredEvent(from: clean) {
            return structured
        }

        let lowercase = clean.lowercased()
        if lowercase.contains("permission") && (lowercase.contains("approve") || lowercase.contains("allow")) {
            return TerminalAgentEvent(kind: .needsInput, title: "Terminal Needs Approval", body: clean)
        }
        if lowercase.contains("input required") || lowercase.contains("waiting for") || lowercase.contains("needs your input") {
            return TerminalAgentEvent(kind: .needsInput, title: "Terminal Needs Input", body: clean)
        }
        if lowercase.contains("error") || lowercase.contains("failed") || lowercase.contains("exception") {
            return TerminalAgentEvent(kind: .error, title: "Terminal Error", body: clean)
        }
        if lowercase.range(of: #"\b(completed|finished|done)\b"#, options: .regularExpression) != nil {
            return TerminalAgentEvent(kind: .done, title: "Terminal Done", body: clean)
        }
        return nil
    }

    private func structuredEvent(from line: String) -> TerminalAgentEvent? {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let eventName = stringValue(object["event"])
            ?? stringValue(object["hook_event_name"])
            ?? stringValue(object["hookEventName"])
            ?? stringValue(object["type"])
            ?? stringValue((object["hookSpecificOutput"] as? [String: Any])?["hookEventName"])

        guard let eventName else { return nil }
        let normalized = eventName.lowercased()
        let message = stringValue(object["message"])
            ?? stringValue(object["reason"])
            ?? stringValue(object["permissionDecisionReason"])
            ?? line

        switch normalized {
        case "stop", "sessionend", "session_end", "taskcompleted", "task_completed", "subagentstop", "subagent_stop":
            return TerminalAgentEvent(kind: .done, title: "Terminal Done", body: message)
        case "notification", "permissionrequest", "permission_request", "elicitation", "elicitation_dialog":
            return TerminalAgentEvent(kind: .needsInput, title: "Terminal Needs Input", body: message)
        case "stopfailure", "stop_failure", "posttoolusefailure", "post_tool_use_failure", "exception", "error":
            return TerminalAgentEvent(kind: .error, title: "Terminal Error", body: message)
        default:
            return nil
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as CustomStringConvertible:
            return value.description
        default:
            return nil
        }
    }
}
