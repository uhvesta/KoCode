import AvestaCore
import SwiftUI

struct TabBarItem: View {
    let tab: any WorkspaceTab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: tab.kind == .terminal ? "terminal" : "text.page")
                Text(tab.title)
                    .lineLimit(1)

                if tab.isClosable {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
    }
}
