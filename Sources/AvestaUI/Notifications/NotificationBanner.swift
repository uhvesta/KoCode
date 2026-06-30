import AvestaCore
import ComposableArchitecture
import SwiftUI

struct NotificationBanner: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        if let banner = store.notificationBanners.first {
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
