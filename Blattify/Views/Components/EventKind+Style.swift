import SwiftUI

extension PlantEvent {
    /// Pot diameter like "21.5 cm" (unit as entered, at most one decimal, no rounding to whole cm).
    static func formattedPotDiameter(_ centimeters: Double) -> String {
        Measurement(value: centimeters, unit: UnitLength.centimeters).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...1)))
        )
    }
}

extension EventKind {
    /// Icon tint used in history and quick actions; matches the activity matrix colors.
    var tint: Color {
        switch self {
        case .watering: .matrixSoaked
        case .fertilizing: .matrixFertilizing
        case .repotting: .matrixRepotting
        case .cutting: .matrixCutting
        case .newLeaf: .matrixNewLeaf
        }
    }
}
