import Testing
@testable import Blattify

@MainActor
struct EventFormattingTests {
    @Test func potDiameterKeepsOneDecimal() {
        let text = PlantEvent.formattedPotDiameter(21.5)
        #expect(text.contains("21.5") || text.contains("21,5"))
        #expect(!text.contains("22"))
    }

    @Test func potDiameterWithoutFractionHasNoDecimals() {
        let text = PlantEvent.formattedPotDiameter(24)
        #expect(text.contains("24"))
        #expect(!text.contains("24.0") && !text.contains("24,0"))
    }
}
