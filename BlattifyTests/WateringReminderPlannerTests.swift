import Foundation
import Testing
@testable import Blattify

struct WateringReminderPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func plant(dueDay: Date, name: String = "Monty") -> WateringReminderPlanner.PlantInput {
        WateringReminderPlanner.PlantInput(id: UUID(), name: name, dueDay: calendar.startOfDay(for: dueDay))
    }

    private let nineAM = 9 * 60

    @Test func futureDueDayFiresAtReminderTime() {
        let input = plant(dueDay: date(11, 10))
        let reminders = WateringReminderPlanner.reminders(for: [input], minutesAfterMidnight: nineAM,
                                                          now: date(11, 6, 15), calendar: calendar)
        #expect(reminders.map(\.fireDate) == [date(11, 10, 9)])
        #expect(reminders.first?.identifier == "watering-\(input.id.uuidString)")
        #expect(reminders.first?.plantName == "Monty")
    }

    @Test func dueTodayBeforeReminderTimeFiresToday() {
        let reminders = WateringReminderPlanner.reminders(for: [plant(dueDay: date(11, 6))], minutesAfterMidnight: nineAM,
                                                          now: date(11, 6, 8, 30), calendar: calendar)
        #expect(reminders.map(\.fireDate) == [date(11, 6, 9)])
    }

    @Test func dueTodayAfterReminderTimeFiresTomorrow() {
        let reminders = WateringReminderPlanner.reminders(for: [plant(dueDay: date(11, 6))], minutesAfterMidnight: nineAM,
                                                          now: date(11, 6, 9, 1), calendar: calendar)
        #expect(reminders.map(\.fireDate) == [date(11, 7, 9)])
    }

    @Test func overdueFiresAtNextReminderTime() {
        let earlyMorning = WateringReminderPlanner.reminders(for: [plant(dueDay: date(11, 1))], minutesAfterMidnight: nineAM,
                                                             now: date(11, 6, 7), calendar: calendar)
        #expect(earlyMorning.map(\.fireDate) == [date(11, 6, 9)])

        let evening = WateringReminderPlanner.reminders(for: [plant(dueDay: date(11, 1))], minutesAfterMidnight: nineAM,
                                                        now: date(11, 6, 20), calendar: calendar)
        #expect(evening.map(\.fireDate) == [date(11, 7, 9)])
    }

    @Test func customReminderTime() {
        let reminders = WateringReminderPlanner.reminders(for: [plant(dueDay: date(11, 10))], minutesAfterMidnight: 18 * 60 + 45,
                                                          now: date(11, 6, 15), calendar: calendar)
        #expect(reminders.map(\.fireDate) == [date(11, 10, 18, 45)])
    }

    @Test func remindersAreSortedAndLimited() {
        let plants = (0..<80).map { offset in
            plant(dueDay: calendar.date(byAdding: .day, value: 80 - offset, to: date(11, 7)) ?? .distantPast, name: "P\(offset)")
        }
        let reminders = WateringReminderPlanner.reminders(for: plants, minutesAfterMidnight: nineAM,
                                                          now: date(11, 6, 12), calendar: calendar)
        #expect(reminders.count == WateringReminderPlanner.maximumCount)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        #expect(reminders.first?.plantName == "P79")
    }

    @Test func identifierRoundTrip() {
        let id = UUID()
        #expect(WateringReminderPlanner.plantID(fromIdentifier: WateringReminderPlanner.identifier(for: id)) == id)
        #expect(WateringReminderPlanner.plantID(fromIdentifier: "other-\(id.uuidString)") == nil)
    }
}
