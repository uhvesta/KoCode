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
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }

            Button("Save Comment", action: save)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
