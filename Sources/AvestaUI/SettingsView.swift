import AvestaCore
import SwiftUI

public struct SettingsView: View {
    let model: ApplicationModel
    public init(model: ApplicationModel) { self.model = model }

    public var body: some View {
        Form {
            Picker("Default Git base branch", selection: Binding(
                get: { model.defaultBaseBranch },
                set: { value in Task { await model.setDefaultBaseBranch(value) } }
            )) {
                Text("origin/main").tag("origin/main")
                Text("origin/master").tag("origin/master")
            }
            Picker("Default terminal scrollback", selection: Binding(
                get: { storageValue(model.globalScrollback) },
                set: { value in Task { await model.setGlobalScrollback(policy(value)) } }
            )) {
                Text("Disabled").tag("disabled")
                Text("10,000 lines").tag("limited")
                Text("Unlimited").tag("unlimited")
            }
            LabeledContent("Database", value: model.config.databaseURL.path)
            LabeledContent("Shared repository cache", value: model.config.cacheRoot.path)
            Text("Ghostty loads your normal configuration. AvestaCode-specific overrides and terminal scrollback choices are stored in SQLite and applied through libghostty configuration APIs.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 560)
    }

    private func storageValue(_ policy: ScrollbackPolicy) -> String {
        switch policy { case .disabled: return "disabled"; case .limited: return "limited"; case .unlimited: return "unlimited" }
    }
    private func policy(_ value: String) -> ScrollbackPolicy {
        switch value { case "disabled": return .disabled; case "unlimited": return .unlimited; default: return .limited(lines: 10_000) }
    }
}
