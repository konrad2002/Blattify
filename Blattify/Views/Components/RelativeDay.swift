import SwiftUI

/// Day-based relative descriptions ("Today", "Yesterday", "3 days ago", "In 2 days").
enum RelativeDay {
    /// Calendar days from `date` to `now`; positive for past dates.
    static func days(from date: Date, to now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func text(for date: Date, now: Date = .now) -> LocalizedStringKey {
        let distance = days(from: date, to: now)
        switch distance {
        case 0:
            return "Today"
        case 1:
            return "Yesterday"
        case -1:
            return "Tomorrow"
        case 2...:
            return "^[\(distance) day](inflect: true) ago"
        default:
            return "In ^[\(-distance) day](inflect: true)"
        }
    }

    /// Text for a due date: "Today", "Tomorrow", "In 3 days" or "2 days overdue".
    static func dueText(for date: Date, now: Date = .now) -> LocalizedStringKey {
        let distance = days(from: date, to: now)
        if distance > 0 {
            return "^[\(distance) day](inflect: true) overdue"
        }
        return text(for: date, now: now)
    }
}
