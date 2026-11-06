import Foundation
import SwiftData
import Testing
@testable import Blattify

@MainActor
struct BackupRoundTripTests {
    private let source: ModelContainer
    private let target: ModelContainer
    private let workDirectory: URL

    init() throws {
        source = try Persistence.makeContainer(inMemory: true)
        target = try Persistence.makeContainer(inMemory: true)
        workDirectory = FileManager.default.temporaryDirectory.appending(path: "BackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        // Sample plants plus photos, a retired code and an event kind from a "newer" version.
        let context = source.mainContext
        SampleData.insert(into: context)
        let plants = try context.fetch(FetchDescriptor<Plant>(sortBy: [SortDescriptor(\.code)]))
        plants.first?.profilePhoto = Data(repeating: 7, count: 512)
        if let event = plants.first?.events?.first {
            let photo = EventPhoto(imageData: Data(repeating: 3, count: 256))
            context.insert(photo)
            photo.event = event
        }
        if let infestation = plants.compactMap({ $0.infestations?.first }).first {
            let photo = EventPhoto(imageData: Data(repeating: 9, count: 128))
            context.insert(photo)
            photo.infestation = infestation
        }
        if let event = plants.last?.events?.first {
            event.kindRaw = "futureKind"
        }
        context.insert(RetiredPlantCode(code: "ZZ-99"))
        try context.save()
    }

    @Test func exportAndImportIntoEmptyStoreRestoresEverything() async throws {
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let snapshot = try BackupExporter.makeSnapshot(from: source.mainContext)
        let archive = try await BackupExporter.writeArchive(snapshot, to: workDirectory)
        #expect(archive.pathExtension == "blattify")

        let restored = try await BackupImporter.readArchive(at: archive)
        let summary = try BackupImporter.merge(restored, into: target.mainContext)

        let sourcePlants = try source.mainContext.fetch(FetchDescriptor<Plant>())
        let targetPlants = try target.mainContext.fetch(FetchDescriptor<Plant>())
        #expect(summary.plantsAdded == sourcePlants.count)
        #expect(summary.codeChanges.isEmpty)
        #expect(targetPlants.count == sourcePlants.count)

        let targetByID = Dictionary(uniqueKeysWithValues: targetPlants.map { ($0.id, $0) })
        for original in sourcePlants {
            let copy = try #require(targetByID[original.id])
            #expect(copy.code == original.code)
            #expect(copy.name == original.name)
            #expect(copy.species == original.species)
            #expect(copy.statusRaw == original.statusRaw)
            #expect(copy.wateringIntervalDays == original.wateringIntervalDays)
            #expect(copy.parent?.id == original.parent?.id)
            #expect(copy.profilePhoto == original.profilePhoto)
            #expect(isClose(copy.createdAt, original.createdAt))
            #expect(isClose(copy.acquiredDate, original.acquiredDate))
            #expect(isClose(copy.statusDate, original.statusDate))

            let originalEvents = Dictionary(uniqueKeysWithValues: (original.events ?? []).map { ($0.id, $0) })
            #expect((copy.events ?? []).count == originalEvents.count)
            for event in copy.events ?? [] {
                let expected = try #require(originalEvents[event.id])
                #expect(event.kindRaw == expected.kindRaw)
                #expect(event.wateringKindRaw == expected.wateringKindRaw)
                #expect(event.fertilizerName == expected.fertilizerName)
                #expect(event.potDiameterCm == expected.potDiameterCm)
                #expect(event.resultingPlantID == expected.resultingPlantID)
                #expect(event.note == expected.note)
                #expect(isClose(event.date, expected.date))
                #expect(Set((event.photos ?? []).compactMap(\.imageData)) == Set((expected.photos ?? []).compactMap(\.imageData)))
            }

            let originalPests = Dictionary(uniqueKeysWithValues: (original.infestations ?? []).map { ($0.id, $0) })
            #expect((copy.infestations ?? []).count == originalPests.count)
            for pest in copy.infestations ?? [] {
                let expected = try #require(originalPests[pest.id])
                #expect(pest.pestTypeRaw == expected.pestTypeRaw)
                #expect(isClose(pest.resolvedDate, expected.resolvedDate))
                #expect(pest.notes == expected.notes)
                #expect((pest.photos ?? []).count == (expected.photos ?? []).count)
            }
        }

        #expect(try target.mainContext.usedPlantCodes().contains("ZZ-99"))
        #expect(try target.mainContext.fetch(FetchDescriptor<EventPhoto>()).count == 2)
    }

    @Test func archiveRejectsFilesThatAreNotBackups() async throws {
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        let bogus = workDirectory.appending(path: "bogus.blattify")
        try Data("not an archive".utf8).write(to: bogus)
        await #expect(throws: BackupImporter.ImportError.unreadableArchive) {
            try await BackupImporter.readArchive(at: bogus)
        }
    }

    @Test(arguments: ["images/ABC-123.jpg", "images/\(UUID().uuidString).jpg"])
    func validImagePaths(path: String) {
        #expect(BackupCoding.isValidImagePath(path))
    }

    @Test(arguments: ["../data.json", "images/../../x.jpg", "/etc/passwd", "images/a b.jpg", "images/x.png", "data.json"])
    func invalidImagePaths(path: String) {
        #expect(!BackupCoding.isValidImagePath(path))
    }

    /// Dates are stored with millisecond precision.
    private func isClose(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): abs(lhs.timeIntervalSince(rhs)) < 0.002
        default: false
        }
    }
}
