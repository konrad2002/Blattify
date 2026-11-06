import Foundation
import UserNotifications

/// Receives notification taps (also on cold launch) and exposes the plant to open.
@Observable
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    /// Set when a watering notification was tapped; the root view opens the plant and clears it.
    var pendingPlantID: UUID?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let value = response.notification.request.content.userInfo[NotificationKeys.plantID] as? String
        guard let id = value.flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run {
            pendingPlantID = id
        }
    }

    /// Show reminders as banners even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
