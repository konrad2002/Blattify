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
    /// Icon tint used in history and quick actions.
    var tint: Color {
        switch self {
        case .watering: .blue
        case .fertilizing: .brown
        case .repotting: .orange
        case .cutting: .purple
        case .newLeaf: .green
        }
    }
}
