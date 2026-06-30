import AvestaCore
import SwiftUI

struct CommentOverlay: View {
    @Binding var text: String
    let save: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $text)
                .font(.body)
                .frame(width: 320, height: 120)
                .accessibilityLabel("Comment Text")
                .accessibilityIdentifier("code-review-comment-text")
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }

            Button("Save Comment", action: save)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("code-review-save-comment")
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
