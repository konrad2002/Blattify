import Foundation
import SwiftData

/// A plant in the user's collection.
///
/// CloudKit requirements: every property is optional or has a default value,
/// relationships are optional, and there are no unique constraints.
@Model
final class Plant {
    var id: UUID = UUID()
    /// Unique `XX-XX` code (see `PlantCode`). Uniqueness is enforced in app logic.
    var code: String = ""
    var name: String = ""
    /// Plant species ("Pflanzenart"), free text.
    var species: String = ""
    var acquiredDate: Date?
    var notes: String = ""
    var statusRaw: String = PlantStatus.active.rawValue
    /// Date the plant was given away or died.
    var statusDate: Date?
    /// Watering reminder interval in days; `nil` means the reminder is off.
    var wateringIntervalDays: Int?
    @Attribute(.externalStorage) var profilePhoto: Data?
    var createdAt: Date = Date.now

    /// The plant this one was grown from as a cutting.
    var parent: Plant?
    /// Cuttings grown from this plant.
    @Relationship(deleteRule: .nullify, inverse: \Plant.parent)
    var children: [Plant]? = []

    @Relationship(deleteRule: .cascade, inverse: \PlantEvent.plant)
    var events: [PlantEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \PestInfestation.plant)
    var infestations: [PestInfestation]? = []

    init(
        id: UUID = UUID(),
        code: String,
        name: String,
        species: String = "",
        acquiredDate: Date? = nil,
        notes: String = "",
        wateringIntervalDays: Int? = nil,
        parent: Plant? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.species = species
        self.acquiredDate = acquiredDate
        self.notes = notes
        self.wateringIntervalDays = wateringIntervalDays
        self.parent = parent
        self.createdAt = createdAt
    }
}

// MARK: - Computed helpers

extension Plant {
    /// Unknown raw values (e.g. from a newer app version) are treated as active.
    var status: PlantStatus {
        get { PlantStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isArchived: Bool { status.isArchived }

    /// Marks the plant as given away or died on `date`.
    func archive(as status: PlantStatus, on date: Date) {
        guard status.isArchived else { return }
        self.status = status
        statusDate = date
    }

    /// Makes an archived plant active again.
    func restore() {
        status = .active
        statusDate = nil
    }

    /// Cuttings sorted by name.
    var sortedChildren: [Plant] {
        (children ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// `true` if this plant is `other` or descends from it (walks up the parent chain).
    /// Used to prevent cycles when choosing a parent plant.
    func isSelfOrDescendant(of other: Plant) -> Bool {
        var current: Plant? = self
        var visited = Set<UUID>()
        while let plant = current, visited.insert(plant.id).inserted {
            if plant == other { return true }
            current = plant.parent
        }
        return false
    }

    /// The most recent event of the given kind.
    func latestEvent(of kind: EventKind) -> PlantEvent? {
        (events ?? [])
            .filter { $0.kind == kind }
            .max { $0.date < $1.date }
    }

    var lastWatering: PlantEvent? { latestEvent(of: .watering) }
    var lastFertilizing: PlantEvent? { latestEvent(of: .fertilizing) }
    var lastRepotting: PlantEvent? { latestEvent(of: .repotting) }
    var lastNewLeaf: PlantEvent? { latestEvent(of: .newLeaf) }

    var activeInfestations: [PestInfestation] {
        (infestations ?? [])
            .filter(\.isActive)
            .sorted { $0.startDate > $1.startDate }
    }

    var hasActiveInfestation: Bool { !activeInfestations.isEmpty }

    /// Start of the day on which the next watering is due, or `nil` if no reminder interval is set.
    /// Counts from the last watering of any kind, or from the creation date if the plant was never watered.
    func nextWateringDate(calendar: Calendar = .current) -> Date? {
        guard let interval = wateringIntervalDays, interval > 0 else { return nil }
        let reference = calendar.startOfDay(for: lastWatering?.date ?? createdAt)
        return calendar.date(byAdding: .day, value: interval, to: reference)
    }

    /// `true` if a watering interval is set and the due day is today or earlier.
    func isWateringDue(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due = nextWateringDate(calendar: calendar) else { return false }
        return calendar.startOfDay(for: date) >= due
    }

    /// Whole calendar days since the last watering, or `nil` if never watered.
    func daysSinceLastWatering(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let last = lastWatering?.date else { return nil }
        let start = calendar.startOfDay(for: last)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}
