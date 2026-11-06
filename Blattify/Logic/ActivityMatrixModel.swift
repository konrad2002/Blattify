import Foundation

/// Event types that can be toggled on and off above the matrix, in display priority order.
nonisolated enum MatrixFilter: String, CaseIterable, Sendable {
    case watering
    case fertilizing
    case pest
    case repotting
    case cutting
    case newLeaf

    var title: LocalizedStringResource {
        switch self {
        case .watering: "Watering"
        case .fertilizing: "Fertilizing"
        case .pest: "Pests"
        case .repotting: "Repotting"
        case .cutting: "Cutting"
        case .newLeaf: "New leaf"
        }
    }
}

/// What a matrix cell segment represents. The raw value is the display priority (lower first).
/// A day has at most one of the watering categories.
nonisolated enum MatrixCategory: Int, CaseIterable, Comparable, Sendable {
    case wateringSoaked
    case wateringShower
    case wateringWet
    case fertilizing
    case pest
    case repotting
    case cutting
    case newLeaf

    init(_ wateringKind: WateringKind) {
        switch wateringKind {
        case .soaked: self = .wateringSoaked
        case .shower: self = .wateringShower
        case .wet: self = .wateringWet
        }
    }

    var filter: MatrixFilter {
        switch self {
        case .wateringSoaked, .wateringShower, .wateringWet: .watering
        case .fertilizing: .fertilizing
        case .pest: .pest
        case .repotting: .repotting
        case .cutting: .cutting
        case .newLeaf: .newLeaf
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .wateringSoaked: "Soaked"
        case .wateringShower: "Shower"
        case .wateringWet: "Moistened"
        case .fertilizing: "Fertilizing"
        case .pest: "Pest infestation"
        case .repotting: "Repotting"
        case .cutting: "Cutting"
        case .newLeaf: "New leaf"
        }
    }

    static func < (lhs: MatrixCategory, rhs: MatrixCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A calendar day, independent of time and time zone once created.
nonisolated struct DayKey: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Year grid for the GitHub-style activity matrix: columns are weeks, rows are weekdays
/// (starting with the calendar's first weekday). Pure value type so it can be unit tested.
nonisolated struct ActivityMatrixModel: Sendable {
    struct EventInput: Sendable {
        let date: Date
        let kind: EventKind
        let wateringKind: WateringKind?
    }

    /// Pest episode; `end == nil` means still active (shown until today).
    struct PestRange: Sendable {
        let start: Date
        let end: Date?
    }

    struct Cell: Identifiable, Sendable {
        let id: DayKey
        /// Start of the day.
        let date: Date
        let column: Int
        let row: Int
        /// Visible categories in priority order, at most `maxSegments` (what is drawn).
        let categories: [MatrixCategory]
        /// All visible categories in priority order (for VoiceOver and day details).
        let allCategories: [MatrixCategory]
        /// More categories than segments are shown.
        let hasMore: Bool
        let isFuture: Bool
        let isToday: Bool
    }

    struct MonthLabel: Sendable {
        let month: Int
        let date: Date
        let column: Int
    }

    static let maxSegments = 4

    let year: Int
    let cells: [Cell]
    let columnCount: Int
    let monthLabels: [MonthLabel]
    /// Row of January 1st (empty cells before it in the first column).
    let firstRowOffset: Int

    init(
        year: Int,
        events: [EventInput],
        pests: [PestRange],
        visibleFilters: Set<MatrixFilter> = Set(MatrixFilter.allCases),
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.year = year
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let nextYearStart = calendar.date(byAdding: .year, value: 1, to: yearStart),
              let lastDayStart = calendar.date(byAdding: .day, value: -1, to: nextYearStart) else {
            cells = []
            columnCount = 0
            monthLabels = []
            firstRowOffset = 0
            return
        }
        let today = calendar.startOfDay(for: now)

        // Collect categories per day.
        var categoriesByDay: [DayKey: Set<MatrixCategory>] = [:]
        var wateringByDay: [DayKey: WateringKind] = [:]
        for event in events where event.date >= yearStart && event.date < nextYearStart {
            let key = DayKey(event.date, calendar: calendar)
            switch event.kind {
            case .watering:
                // Unknown watering kinds count as soaked; several waterings keep the highest priority.
                let kind = event.wateringKind ?? .soaked
                if let existing = wateringByDay[key], existing.priority >= kind.priority { continue }
                wateringByDay[key] = kind
            case .fertilizing:
                categoriesByDay[key, default: []].insert(.fertilizing)
            case .repotting:
                categoriesByDay[key, default: []].insert(.repotting)
            case .cutting:
                categoriesByDay[key, default: []].insert(.cutting)
            case .newLeaf:
                categoriesByDay[key, default: []].insert(.newLeaf)
            }
        }
        for (key, kind) in wateringByDay {
            categoriesByDay[key, default: []].insert(MatrixCategory(kind))
        }

        // Pest episodes cover every day from start to end (inclusive), clipped to this year.
        for pest in pests {
            var day = max(calendar.startOfDay(for: pest.start), yearStart)
            let end = min(calendar.startOfDay(for: pest.end ?? now), lastDayStart)
            while day <= end {
                categoriesByDay[DayKey(day, calendar: calendar), default: []].insert(.pest)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        // Lay out the year.
        let offset = (calendar.component(.weekday, from: yearStart) - calendar.firstWeekday + 7) % 7
        var cells: [Cell] = []
        var monthLabels: [MonthLabel] = []
        var day = yearStart
        var index = 0
        while day < nextYearStart {
            let position = index + offset
            let column = position / 7
            let key = DayKey(day, calendar: calendar)
            let visible = (categoriesByDay[key] ?? [])
                .filter { visibleFilters.contains($0.filter) }
                .sorted()
            cells.append(Cell(
                id: key,
                date: day,
                column: column,
                row: position % 7,
                categories: Array(visible.prefix(Self.maxSegments)),
                allCategories: visible,
                hasMore: visible.count > Self.maxSegments,
                isFuture: day > today,
                isToday: day == today
            ))
            if key.day == 1 {
                monthLabels.append(MonthLabel(month: key.month, date: day, column: column))
            }
            index += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        self.cells = cells
        self.monthLabels = monthLabels
        self.firstRowOffset = offset
        columnCount = (cells.last?.column ?? -1) + 1
    }

    /// The cell at a grid position, or `nil` for the empty slots before Jan 1 / after Dec 31.
    func cell(column: Int, row: Int) -> Cell? {
        guard (0..<7).contains(row) else { return nil }
        let index = column * 7 + row - firstRowOffset
        return cells.indices.contains(index) ? cells[index] : nil
    }

    /// Years that can be browsed: from the earliest relevant date to the current year.
    static func yearRange(earliest: Date, now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Int> {
        let current = calendar.component(.year, from: now)
        let first = min(calendar.component(.year, from: earliest), current)
        return first...current
    }
}
