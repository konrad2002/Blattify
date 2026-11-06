import Foundation
import Testing
@testable import Blattify

struct ActivityMatrixModelTests {
    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private let monday = Self.calendar(firstWeekday: 2)
    private let sunday = Self.calendar(firstWeekday: 1)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func cell(_ model: ActivityMatrixModel, _ month: Int, _ day: Int) -> ActivityMatrixModel.Cell? {
        model.cells.first { $0.id.month == month && $0.id.day == day }
    }

    @Test func leapYearHas366Days() {
        let now = date(2030, 1, 1, in: monday)
        #expect(ActivityMatrixModel(year: 2028, events: [], pests: [], calendar: monday, now: now).cells.count == 366)
        #expect(ActivityMatrixModel(year: 2026, events: [], pests: [], calendar: monday, now: now).cells.count == 365)
    }

    @Test func firstWeekdayDeterminesRows() {
        // 1 Jan 2026 is a Thursday.
        let now = date(2026, 6, 1, in: monday)
        let mondayModel = ActivityMatrixModel(year: 2026, events: [], pests: [], calendar: monday, now: now)
        let sundayModel = ActivityMatrixModel(year: 2026, events: [], pests: [], calendar: sunday, now: now)

        #expect(mondayModel.firstRowOffset == 3)
        #expect(sundayModel.firstRowOffset == 4)
        #expect(cell(mondayModel, 1, 1)?.row == 3)
        #expect(cell(mondayModel, 1, 1)?.column == 0)
        // Monday 5 Jan starts the second column with a Monday-first calendar.
        #expect(cell(mondayModel, 1, 5)?.row == 0)
        #expect(cell(mondayModel, 1, 5)?.column == 1)
        // Sunday 4 Jan starts the second column with a Sunday-first calendar.
        #expect(cell(sundayModel, 1, 4)?.row == 0)
        #expect(cell(sundayModel, 1, 4)?.column == 1)
    }

    @Test func yearBoundariesAndGridLookup() {
        let now = date(2026, 6, 1, in: monday)
        let model = ActivityMatrixModel(year: 2026, events: [], pests: [], calendar: monday, now: now)
        let last = cell(model, 12, 31)
        #expect(last != nil)
        #expect(model.columnCount == (last?.column ?? 0) + 1)
        #expect(model.cell(column: 0, row: 0) == nil) // Monday 29 Dec 2025 is not part of 2026
        #expect(model.cell(column: 0, row: 3)?.id == DayKey(date(2026, 1, 1, in: monday), calendar: monday))
        #expect(model.monthLabels.count == 12)
        #expect(model.monthLabels.first?.column == 0)
    }

    @Test func eventsOutsideTheYearAreIgnored() {
        let now = date(2026, 6, 1, in: monday)
        let events = [
            ActivityMatrixModel.EventInput(date: date(2025, 12, 31, hour: 23, in: monday), kind: .fertilizing, wateringKind: nil),
            ActivityMatrixModel.EventInput(date: date(2027, 1, 1, hour: 0, in: monday), kind: .fertilizing, wateringKind: nil),
        ]
        let model = ActivityMatrixModel(year: 2026, events: events, pests: [], calendar: monday, now: now)
        #expect(model.cells.allSatisfy { $0.categories.isEmpty })
    }

    @Test func wateringPriorityKeepsStrongestKind() {
        let now = date(2026, 6, 1, in: monday)
        let day = date(2026, 3, 3, in: monday)
        let events = [
            ActivityMatrixModel.EventInput(date: day, kind: .watering, wateringKind: .wet),
            ActivityMatrixModel.EventInput(date: day.addingTimeInterval(3600), kind: .watering, wateringKind: .soaked),
            ActivityMatrixModel.EventInput(date: day.addingTimeInterval(7200), kind: .watering, wateringKind: .shower),
        ]
        let model = ActivityMatrixModel(year: 2026, events: events, pests: [], calendar: monday, now: now)
        #expect(cell(model, 3, 3)?.categories == [.wateringSoaked])

        let showerAndWet = ActivityMatrixModel(year: 2026, events: [events[0], events[2]], pests: [],
                                               calendar: monday, now: now)
        #expect(cell(showerAndWet, 3, 3)?.categories == [.wateringShower])
    }

    @Test func pestRangeSpanningYearsIsClipped() {
        let now = date(2026, 6, 1, in: monday)
        let pest = ActivityMatrixModel.PestRange(start: date(2025, 12, 20, in: monday), end: date(2026, 1, 10, in: monday))
        let model = ActivityMatrixModel(year: 2026, events: [], pests: [pest], calendar: monday, now: now)
        #expect(cell(model, 1, 1)?.categories == [.pest])
        #expect(cell(model, 1, 10)?.categories == [.pest])
        #expect(cell(model, 1, 11)?.categories.isEmpty == true)

        let previousYear = ActivityMatrixModel(year: 2025, events: [], pests: [pest], calendar: monday, now: now)
        #expect(cell(previousYear, 12, 19)?.categories.isEmpty == true)
        #expect(cell(previousYear, 12, 20)?.categories == [.pest])
        #expect(cell(previousYear, 12, 31)?.categories == [.pest])
    }

    @Test func activePestLastsUntilToday() {
        let now = date(2026, 6, 15, in: monday)
        let pest = ActivityMatrixModel.PestRange(start: date(2026, 6, 10, in: monday), end: nil)
        let model = ActivityMatrixModel(year: 2026, events: [], pests: [pest], calendar: monday, now: now)
        #expect(cell(model, 6, 15)?.categories == [.pest])
        #expect(cell(model, 6, 16)?.categories.isEmpty == true)
        #expect(cell(model, 6, 16)?.isFuture == true)
        #expect(cell(model, 6, 15)?.isToday == true)
    }

    @Test func categoriesAreOrderedLimitedAndFiltered() {
        let now = date(2026, 6, 1, in: monday)
        let day = date(2026, 4, 2, in: monday)
        let events = [
            ActivityMatrixModel.EventInput(date: day, kind: .newLeaf, wateringKind: nil),
            ActivityMatrixModel.EventInput(date: day, kind: .cutting, wateringKind: nil),
            ActivityMatrixModel.EventInput(date: day, kind: .repotting, wateringKind: nil),
            ActivityMatrixModel.EventInput(date: day, kind: .fertilizing, wateringKind: nil),
            ActivityMatrixModel.EventInput(date: day, kind: .watering, wateringKind: .wet),
        ]
        let pest = ActivityMatrixModel.PestRange(start: day, end: day)

        let all = ActivityMatrixModel(year: 2026, events: events, pests: [pest], calendar: monday, now: now)
        #expect(cell(all, 4, 2)?.categories == [.wateringWet, .fertilizing, .pest, .repotting])
        #expect(cell(all, 4, 2)?.hasMore == true)

        let filtered = ActivityMatrixModel(year: 2026, events: events, pests: [pest],
                                           visibleFilters: [.cutting, .newLeaf], calendar: monday, now: now)
        #expect(cell(filtered, 4, 2)?.categories == [.cutting, .newLeaf])
        #expect(cell(filtered, 4, 2)?.hasMore == false)
    }

    @Test func yearRangeStartsAtEarliestDate() {
        let now = date(2026, 6, 1, in: monday)
        #expect(ActivityMatrixModel.yearRange(earliest: date(2024, 5, 1, in: monday), now: now, calendar: monday) == 2024...2026)
        #expect(ActivityMatrixModel.yearRange(earliest: date(2027, 5, 1, in: monday), now: now, calendar: monday) == 2026...2026)
    }
}
