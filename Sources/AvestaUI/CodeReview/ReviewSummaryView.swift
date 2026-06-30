import AvestaCore
import SwiftUI

struct ReviewSummaryView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            Text(markdown)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
