import Foundation
import SwiftData
import Testing
@testable import Blattify

@MainActor
struct AppRouterTests {
    private let container: ModelContainer
    private let plant: Plant

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        plant = Plant(code: "AB-23", name: "Monty")
        container.mainContext.insert(plant)
        try container.mainContext.save()
    }

    @Test func deepLinkOpensKnownPlant() throws {
        let router = AppRouter()
        let url = try #require(URL(string: "blattify://plant/ab-23"))
        router.handle(url, in: container.mainContext)
        #expect(router.path == [.plant(plant)])
        #expect(router.unknownCode == nil)
    }

    @Test func deepLinkWithUnknownCodeShowsAlert() throws {
        let router = AppRouter()
        let url = try #require(URL(string: "blattify://plant/ZZ-ZZ"))
        router.handle(url, in: container.mainContext)
        #expect(router.path.isEmpty)
        #expect(router.unknownCode?.rawValue == "ZZ-ZZ")
    }

    @Test func foreignURLIsIgnored() throws {
        let router = AppRouter()
        let url = try #require(URL(string: "https://example.com/plant/AB-23"))
        router.handle(url, in: container.mainContext)
        #expect(router.path.isEmpty)
        #expect(router.unknownCode == nil)
    }

    @Test func scannedCodeOpensAfterScannerDismissal() throws {
        let router = AppRouter()
        router.isScanning = true
        router.didScan(try #require(PlantCode("AB-23")))
        #expect(!router.isScanning)
        #expect(router.path.isEmpty)

        router.scannerDismissed(in: container.mainContext)
        #expect(router.path == [.plant(plant)])
    }

    @Test func labelOpensAfterCreatedPlantSheetDismissal() {
        let router = AppRouter()
        router.createPlant()
        router.didCreate(plant)
        #expect(router.path == [.plant(plant)])
        #expect(router.labelPlant == nil)

        router.newPlantSheetDismissed()
        #expect(router.labelPlant == plant)
    }

    @Test func dismissingFormWithoutSavingShowsNoLabel() {
        let router = AppRouter()
        router.createPlant()
        router.newPlantSheetDismissed()
        #expect(router.labelPlant == nil)
    }
}
