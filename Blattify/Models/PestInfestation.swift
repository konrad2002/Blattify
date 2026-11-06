import Foundation
import SwiftData

/// A pest infestation episode from `startDate` until `resolvedDate` (`nil` = still active).
@Model
final class PestInfestation {
    var id: UUID = UUID()
    var pestTypeRaw: String = PestType.other.rawValue
    /// Used when the pest type is `other`.
    var customPestName: String?
    var startDate: Date = Date.now
    var resolvedDate: Date?
    /// Treatments and observations.
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \EventPhoto.infestation)
    var photos: [EventPhoto]? = []

    var plant: Plant?

    init(
        id: UUID = UUID(),
        pestType: PestType,
        customPestName: String? = nil,
        startDate: Date = .now,
        resolvedDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.pestTypeRaw = pestType.rawValue
        self.customPestName = customPestName
        self.startDate = startDate
        self.resolvedDate = resolvedDate
        self.notes = notes
    }
}

extension PestInfestation {
    /// Unknown raw values are treated as `other`.
    var pestType: PestType {
        get { PestType(rawValue: pestTypeRaw) ?? .other }
        set { pestTypeRaw = newValue.rawValue }
    }

    var isActive: Bool { resolvedDate == nil }
}
