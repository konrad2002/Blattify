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

    /// A new code that is not used by any plant and was never retired.
    func makeUniquePlantCode() throws -> PlantCode {
        try PlantCode.generate(excluding: usedPlantCodes())
    }
}
