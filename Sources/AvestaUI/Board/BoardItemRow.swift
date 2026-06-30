import AvestaCore
import SwiftUI

struct BoardItemRow: View {
    let item: BoardItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }

            Text(item.content)
                .font(.caption.monospaced())
                .lineLimit(isExpanded ? nil : 4)
                .textSelection(.enabled)

            Text(item.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
        .padding(.vertical, 6)
    }
}
