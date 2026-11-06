import Foundation
import SwiftData

extension ModelContext {
    /// All plants with the given code. Normally zero or one; more than one only after a sync collision.
    func plants(withCode input: String) throws -> [Plant] {
        guard let code = PlantCode.normalize(input) else { return [] }
        let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.code == code })
        return try fetch(descriptor)
    }

    /// Codes that must not be handed out: codes of all plants (including archived) and retired codes.
    func usedPlantCodes() throws -> Set<String> {
        let plantCodes = try fetch(FetchDescriptor<Plant>()).map(\.code)
        let retiredCodes = try fetch(FetchDescriptor<RetiredPlantCode>()).map(\.code)
        return Set(plantCodes + retiredCodes)
    }

    /// Distinct, non-empty values of a text field across all events of `kind`, most recently used first.
    /// Used for suggestions such as fertilizer names or substrates.
    func recentEventValues(of kind: EventKind, _ value: (PlantEvent) -> String?) throws -> [String] {
        let rawKind = kind.rawValue
        let descriptor = FetchDescriptor<PlantEvent>(
            predicate: #Predicate { $0.kindRaw == rawKind },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        var seen = Set<String>()
        var result: [String] = []
        for event in try fetch(descriptor) {
            guard let text = value(event)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  seen.insert(text).inserted else { continue }
            result.append(text)
        }
        return result
    }

    /// Deletes a plant with its events, infestations and photos. Its code is retired so it is never
    /// handed out again; cuttings keep existing without a parent.
    func deletePermanently(_ plant: Plant) throws {
        if !plant.code.isEmpty {
            insert(RetiredPlantCode(code: plant.code))
        }
        for child in plant.children ?? [] {
            child.parent = nil
        }
        delete(plant)
        try save()
    }

    /// A new code that is not used by any plant and was never retired.
    func makeUniquePlantCode() throws -> PlantCode {
        try PlantCode.generate(excluding: usedPlantCodes())
    }
}
