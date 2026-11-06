import Foundation
import SwiftData

/// A dated care event. Kind-specific fields are only set for the matching `kind`.
@Model
final class PlantEvent {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kindRaw: String = EventKind.watering.rawValue

    /// Watering only.
    var wateringKindRaw: String?
    /// Fertilizing only.
    var fertilizerName: String?
    /// Fertilizing only, free text (e.g. "2 ml/L").
    var fertilizerAmount: String?
    /// Repotting only.
    var potDiameterCm: Double?
    /// Repotting only.
    var substrate: String?
    /// Cutting only: the plant created from this cutting.
    var resultingPlantID: UUID?

    var note: String = ""

    @Relationship(deleteRule: .cascade, inverse: \EventPhoto.event)
    var photos: [EventPhoto]? = []

    var plant: Plant?

    init(
        id: UUID = UUID(),
        kind: EventKind,
        date: Date = .now,
        wateringKind: WateringKind? = nil,
        note: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.date = date
        self.wateringKindRaw = wateringKind?.rawValue
        self.note = note
    }
}

extension PlantEvent {
    /// `nil` for raw values this app version does not know (e.g. synced from a newer version).
    var kind: EventKind? { EventKind(rawValue: kindRaw) }

    var wateringKind: WateringKind? {
        get { wateringKindRaw.flatMap(WateringKind.init(rawValue:)) }
        set { wateringKindRaw = newValue?.rawValue }
    }
}
