import SwiftUI

extension MatrixCategory {
    /// Asset catalog colors with light and dark variants.
    var color: Color {
        switch self {
        case .wateringSoaked: .matrixSoaked
        case .wateringShower: .matrixShower
        case .wateringWet: .matrixWet
        case .fertilizing: .matrixFertilizing
        case .pest: .matrixPest
        case .repotting: .matrixRepotting
        case .cutting: .matrixCutting
        case .newLeaf: .matrixNewLeaf
        }
    }
}

extension MatrixFilter {
    /// Representative color for the filter chip.
    var color: Color {
        switch self {
        case .watering: .matrixSoaked
        case .fertilizing: .matrixFertilizing
        case .pest: .matrixPest
        case .repotting: .matrixRepotting
        case .cutting: .matrixCutting
        case .newLeaf: .matrixNewLeaf
        }
    }
}

extension ActivityMatrixModel {
    /// Builds the matrix for one year of a plant.
    @MainActor
    init(plant: Plant, year: Int, visibleFilters: Set<MatrixFilter>, now: Date = .now) {
        let events = (plant.events ?? []).compactMap { event -> EventInput? in
            guard let kind = event.kind else { return nil }
            return EventInput(date: event.date, kind: kind, wateringKind: event.wateringKind)
        }
        let pests = (plant.infestations ?? []).map { PestRange(start: $0.startDate, end: $0.resolvedDate) }
        self.init(year: year, events: events, pests: pests, visibleFilters: visibleFilters, now: now)
    }

    /// Years from the plant's first event, pest or creation until now.
    @MainActor
    static func yearRange(for plant: Plant, now: Date = .now) -> ClosedRange<Int> {
        let dates = [plant.createdAt]
            + (plant.events ?? []).map(\.date)
            + (plant.infestations ?? []).map(\.startDate)
        return yearRange(earliest: dates.min() ?? now, now: now)
    }
}
