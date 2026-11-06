import Foundation
import UserNotifications

/// The time of day watering reminders are sent, stored in `UserDefaults`.
nonisolated enum ReminderSettings {
    static let minutesKey = "reminderMinutesAfterMidnight"
    /// 09:00
    static let defaultMinutes = 9 * 60

    static var minutesAfterMidnight: Int {
        UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes
    }
}

/// Talks to `UNUserNotificationCenter`: permission and replacing Blattify's watering notifications.
enum ReminderScheduler {
    private static var center: UNUserNotificationCenter { .current() }

    /// `true` if notifications may be shown (asks the user the first time).
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    static func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Replaces all pending watering notifications with `reminders` and removes delivered ones
    /// for plants that are no longer due. Does nothing without permission (never asks).
    static func apply(_ reminders: [WateringReminderPlanner.Reminder], duePlantIDs: Set<UUID>) async {
        let status = await center.notificationSettings().authorizationStatus
        guard [.authorized, .provisional, .ephemeral].contains(status) else { return }

        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(WateringReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let outdatedDelivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { identifier in
                guard let id = WateringReminderPlanner.plantID(fromIdentifier: identifier) else { return false }
                return !duePlantIDs.contains(id)
            }
        center.removeDeliveredNotifications(withIdentifiers: outdatedDelivered)

        let calendar = Calendar.current
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Time to water \(reminder.plantName)")
            content.body = String(localized: "Tap to open the plant in Blattify.")
            content.sound = .default
            content.threadIdentifier = "watering"
            content.userInfo = [NotificationKeys.plantID: reminder.plantID.uuidString]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                // A single failed reminder must not stop the others; it is retried on the next reschedule.
                continue
            }
        }
    }
}

nonisolated enum NotificationKeys {
    static let plantID = "plantID"
}
