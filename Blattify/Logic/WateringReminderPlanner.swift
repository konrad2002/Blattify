import Foundation

/// Decides when watering reminders fire. Pure logic, independent of `UserNotifications`.
nonisolated enum WateringReminderPlanner {
    struct PlantInput: Sendable {
        let id: UUID
        let name: String
        /// Start of the day the next watering is due.
        let dueDay: Date
    }

    struct Reminder: Sendable, Equatable {
        let identifier: String
        let plantID: UUID
        let plantName: String
        let fireDate: Date
    }

    static let identifierPrefix = "watering-"
    /// iOS keeps at most 64 pending local notifications per app; stay below that.
    static let maximumCount = 60

    static func identifier(for plantID: UUID) -> String {
        identifierPrefix + plantID.uuidString
    }

    static func plantID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(identifierPrefix.count)))
    }

    /// One reminder per plant at `minutesAfterMidnight` on its due day. If that moment has already
    /// passed (due today but too late, or overdue), the reminder fires at the next reminder time instead.
    /// Sorted by fire date and limited to `maximumCount`.
    static func reminders(
        for plants: [PlantInput],
        minutesAfterMidnight: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Reminder] {
        let hour = minutesAfterMidnight / 60
        let minute = minutesAfterMidnight % 60

        func reminderTime(on day: Date) -> Date? {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }

        let nextReminderTime: Date? = {
            guard let today = reminderTime(on: now) else { return nil }
            if today > now { return today }
            return calendar.date(byAdding: .day, value: 1, to: today)
        }()

        let reminders = plants.compactMap { plant -> Reminder? in
            guard let onDueDay = reminderTime(on: plant.dueDay) else { return nil }
            let fireDate = onDueDay > now ? onDueDay : nextReminderTime
            return fireDate.map {
                Reminder(identifier: identifier(for: plant.id), plantID: plant.id, plantName: plant.name, fireDate: $0)
            }
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(maximumCount))
    }
}
