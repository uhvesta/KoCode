import AvestaNotifications
import SwiftUI

struct NotificationBanner: View {
    @Environment(NotificationService.self) private var service

    var body: some View {
        if let banner = service.inAppBanners.first {
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
