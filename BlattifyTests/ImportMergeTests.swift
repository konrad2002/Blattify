import Foundation
import SwiftData
import Testing
@testable import Blattify

@MainActor
struct ImportMergeTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
    }

    // MARK: - Helpers

    private func plantDTO(
        id: UUID = UUID(),
        code: String,
        name: String,
        species: String = "",
        notes: String = "",
        parentID: UUID? = nil,
        events: [EventDTO] = []
    ) -> PlantDTO {
        PlantDTO(id: id, code: code, name: name, species: species, acquiredDate: nil, notes: notes,
                 status: PlantStatus.active.rawValue, statusDate: nil, wateringIntervalDays: nil,
                 parentID: parentID, profilePhotoFile: nil, createdAt: .now, events: events, infestations: [])
    }

    private func eventDTO(id: UUID = UUID(), photos: [PhotoDTO] = []) -> EventDTO {
        EventDTO(id: id, date: .now, kind: EventKind.watering.rawValue, wateringKind: WateringKind.soaked.rawValue,
                 fertilizerName: nil, fertilizerAmount: nil, potDiameterCm: nil, substrate: nil,
                 resultingPlantID: nil, note: "", photos: photos)
    }

    private func snapshot(_ plants: [PlantDTO], files: [String: Data] = [:], version: Int = 1) -> BackupSnapshot {
        BackupSnapshot(
            backup: BackupDTO(formatVersion: version, exportedAt: .now, appVersion: "1.0", plants: plants, retiredCodes: []),
            files: files
        )
    }

    // MARK: - Tests

    @Test func repeatedImportCreatesNoDuplicates() throws {
        let photoID = UUID()
        let path = BackupCoding.photoPath(for: photoID)
        let backup = snapshot(
            [plantDTO(code: "AB-23", name: "Monty",
                      events: [eventDTO(photos: [PhotoDTO(id: photoID, file: path, createdAt: .now)]), eventDTO()])],
            files: [path: Data([1, 2, 3])]
        )

        let first = try BackupImporter.merge(backup, into: context)
        #expect(first.plantsAdded == 1)
        #expect(first.eventsAdded == 2)
        #expect(first.photosAdded == 1)

        let second = try BackupImporter.merge(backup, into: context)
        #expect(second.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Plant>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PlantEvent>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<EventPhoto>()).count == 1)
    }

    @Test func localValuesWinAndEmptyFieldsAreFilled() throws {
        let local = Plant(code: "AB-23", name: "Local name", species: "", notes: "Local notes")
        context.insert(local)
        try context.save()

        let summary = try BackupImporter.merge(
            snapshot([plantDTO(id: local.id, code: "AB-23", name: "Imported name", species: "Ficus", notes: "Imported notes")]),
            into: context
        )

        #expect(summary.plantsAdded == 0)
        #expect(summary.plantsUpdated == 1)
        #expect(local.name == "Local name")
        #expect(local.notes == "Local notes")
        #expect(local.species == "Ficus")
    }

    @Test func plantsAreMatchedByCodeWhenIDsDiffer() throws {
        let local = Plant(code: "AB-23", name: "Monty")
        context.insert(local)
        try context.save()

        let summary = try BackupImporter.merge(snapshot([plantDTO(code: "AB-23", name: "Monty", events: [eventDTO()])]),
                                               into: context)

        #expect(summary.plantsAdded == 0)
        #expect(summary.eventsAdded == 1)
        #expect(try context.fetch(FetchDescriptor<Plant>()).count == 1)
        #expect(local.events?.count == 1)
    }

    @Test func retiredCodeGetsNewCode() throws {
        context.insert(RetiredPlantCode(code: "AB-23"))
        try context.save()

        let summary = try BackupImporter.merge(snapshot([plantDTO(code: "AB-23", name: "Monty")]), into: context)

        let plant = try #require(try context.fetch(FetchDescriptor<Plant>()).first)
        #expect(summary.plantsAdded == 1)
        #expect(summary.codeChanges.count == 1)
        #expect(summary.codeChanges.first?.oldCode == "AB-23")
        #expect(plant.code != "AB-23")
        #expect(PlantCode.isValid(plant.code))
    }

    @Test func duplicateCodeInsideBackupGetsNewCode() throws {
        let summary = try BackupImporter.merge(
            snapshot([plantDTO(code: "AB-23", name: "First"), plantDTO(code: "AB-23", name: "Second")]),
            into: context
        )
        let codes = try context.fetch(FetchDescriptor<Plant>()).map(\.code)
        #expect(summary.plantsAdded == 2)
        #expect(summary.codeChanges.map(\.plantName) == ["Second"])
        #expect(Set(codes).count == 2)
    }

    @Test func parentRelationsAreResolved() throws {
        let parentID = UUID()
        _ = try BackupImporter.merge(
            snapshot([
                plantDTO(code: "CD-45", name: "Child", parentID: parentID),
                plantDTO(id: parentID, code: "AB-23", name: "Parent"),
            ]),
            into: context
        )
        let child = try #require(try context.fetch(FetchDescriptor<Plant>()).first { $0.name == "Child" })
        #expect(child.parent?.id == parentID)
    }

    @Test func newerFormatIsRejected() throws {
        #expect(throws: BackupImporter.ImportError.newerFormat(2)) {
            try BackupImporter.merge(snapshot([plantDTO(code: "AB-23", name: "Monty")], version: 2), into: context)
        }
        #expect(try context.fetch(FetchDescriptor<Plant>()).isEmpty)
    }
}
