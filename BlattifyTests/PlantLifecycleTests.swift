import Foundation
import SwiftData
import Testing
@testable import Blattify

@MainActor
struct PlantLifecycleTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
    }

    @Test func archiveAndRestore() {
        let plant = Plant(code: "AB-23", name: "Monty")
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        plant.archive(as: .died, on: date)
        #expect(plant.status == .died)
        #expect(plant.statusDate == date)
        #expect(plant.isArchived)

        plant.restore()
        #expect(plant.status == .active)
        #expect(plant.statusDate == nil)
        #expect(!plant.isArchived)
    }

    @Test func archivingAsActiveIsIgnored() {
        let plant = Plant(code: "AB-23", name: "Monty")
        plant.archive(as: .active, on: .now)
        #expect(plant.statusDate == nil)
    }

    @Test func permanentDeleteRetiresCodeKeepsCuttingsAndRemovesEntries() throws {
        let parent = Plant(code: "AB-23", name: "Monty")
        let cutting = Plant(code: "CD-45", name: "Monty Jr.", parent: parent)
        context.insert(parent)
        context.insert(cutting)
        let event = PlantEvent(kind: .watering, wateringKind: .soaked)
        context.insert(event)
        event.plant = parent
        let photo = EventPhoto(imageData: Data([1, 2, 3]))
        context.insert(photo)
        photo.event = event
        let pest = PestInfestation(pestType: .thrips)
        context.insert(pest)
        pest.plant = parent
        try context.save()

        try context.deletePermanently(parent)

        let plants = try context.fetch(FetchDescriptor<Plant>())
        #expect(plants.map(\.name) == ["Monty Jr."])
        #expect(cutting.parent == nil)
        #expect(try context.fetch(FetchDescriptor<PlantEvent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<EventPhoto>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PestInfestation>()).isEmpty)

        // The code of the deleted plant stays blocked.
        #expect(try context.usedPlantCodes() == ["AB-23", "CD-45"])
        #expect(try context.plants(withCode: "AB-23").isEmpty)
    }

    @Test func cuttingTreeHelpers() throws {
        let parent = Plant(code: "AB-23", name: "Monty")
        let second = Plant(code: "CD-45", name: "Zoe", parent: parent)
        let first = Plant(code: "EF-67", name: "Anna", parent: parent)
        let grandchild = Plant(code: "GH-89", name: "Tiny", parent: first)
        [parent, second, first, grandchild].forEach(context.insert)
        try context.save()

        #expect(parent.sortedChildren.map(\.name) == ["Anna", "Zoe"])
        #expect(grandchild.isSelfOrDescendant(of: parent))
        #expect(!parent.isSelfOrDescendant(of: grandchild))
    }

    @Test func pestDisplayName() {
        let custom = PestInfestation(pestType: .other, customPestName: "  Springtails ")
        #expect(custom.displayName == "Springtails")

        let emptyCustom = PestInfestation(pestType: .other, customPestName: " ")
        #expect(emptyCustom.displayName == String(localized: PestType.other.title))

        // A custom name is ignored for predefined types.
        let thrips = PestInfestation(pestType: .thrips, customPestName: "ignored")
        #expect(thrips.displayName == String(localized: PestType.thrips.title))
    }
}
