import AvestaCore
import SwiftUI

struct NotificationBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let banner = appState.notificationBanners.first {
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.headline)
                Text(banner.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 8)
        }
    }
}
