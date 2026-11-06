import Foundation
import SwiftData

/// Sample plants for SwiftUI previews.
enum SampleData {
    /// In-memory container filled with sample data.
    static func makePreviewContainer() -> ModelContainer {
        do {
            let container = try Persistence.makeContainer(inMemory: true)
            insert(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }

    /// Inserts 5 plants with events spread over the current and previous year,
    /// one cutting relation and one active pest infestation.
    static func insert(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }

        let monstera = Plant(code: "MN-24", name: "Monty", species: "Monstera deliciosa",
                             acquiredDate: daysAgo(600), wateringIntervalDays: 7, createdAt: daysAgo(600))
        let cutting = Plant(code: "MC-35", name: "Monty Jr.", species: "Monstera deliciosa",
                            acquiredDate: daysAgo(120), wateringIntervalDays: 5, parent: monstera,
                            createdAt: daysAgo(120))
        let pothos = Plant(code: "PT-7K", name: "Golden Pothos", species: "Epipremnum aureum",
                           acquiredDate: daysAgo(400), wateringIntervalDays: 6, createdAt: daysAgo(400))
        let calathea = Plant(code: "CA-9X", name: "Calathea", species: "Calathea orbifolia",
                             acquiredDate: daysAgo(200), wateringIntervalDays: 4, createdAt: daysAgo(200))
        let cactus = Plant(code: "KT-3R", name: "Spike", species: "Echinopsis",
                           acquiredDate: daysAgo(900), createdAt: daysAgo(900))
        cactus.status = .givenAway
        cactus.statusDate = daysAgo(30)

        let plants = [monstera, cutting, pothos, calathea, cactus]
        plants.forEach(context.insert)

        // Regular waterings with rotating kinds over the last ~20 months.
        let kinds = WateringKind.allCases
        for (index, plant) in plants.enumerated() {
            let interval = plant.wateringIntervalDays ?? 14
            for (step, day) in stride(from: 3 + index, through: 600, by: interval).enumerated() {
                let event = PlantEvent(kind: .watering, date: daysAgo(day), wateringKind: kinds[step % kinds.count])
                event.plant = plant
            }
            for day in stride(from: 20 + index * 3, through: 600, by: 30) {
                let event = PlantEvent(kind: .fertilizing, date: daysAgo(day))
                event.fertilizerName = "Compo Grünpflanzendünger"
                event.fertilizerAmount = "5 ml/L"
                event.plant = plant
            }
            for day in stride(from: 10 + index, through: 300, by: 45) {
                PlantEvent(kind: .newLeaf, date: daysAgo(day)).plant = plant
            }
        }

        let repotting = PlantEvent(kind: .repotting, date: daysAgo(250), note: "Roots were circling")
        repotting.potDiameterCm = 24
        repotting.substrate = "Aroid mix"
        repotting.plant = monstera

        let cuttingEvent = PlantEvent(kind: .cutting, date: daysAgo(120))
        cuttingEvent.resultingPlantID = cutting.id
        cuttingEvent.plant = monstera

        let activePest = PestInfestation(pestType: .thrips, startDate: daysAgo(12), notes: "Sprayed with neem oil")
        activePest.plant = calathea

        let resolvedPest = PestInfestation(pestType: .fungusGnats, startDate: daysAgo(180),
                                           resolvedDate: daysAgo(150), notes: "Yellow sticky traps")
        resolvedPest.plant = pothos
    }
}
