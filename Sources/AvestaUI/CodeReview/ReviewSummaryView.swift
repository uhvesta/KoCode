import AvestaCore
import SwiftUI

struct ReviewSummaryView: View {
    let session: CodeReviewSession

    var body: some View {
        ScrollView {
            Text(session.toMarkdown())
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
