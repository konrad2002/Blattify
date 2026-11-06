import Foundation

/// Lifecycle status of a plant. Archived plants (`givenAway`, `died`) are hidden from the main list.
nonisolated enum PlantStatus: String, Codable, CaseIterable, Sendable {
    case active
    case givenAway
    case died

    var title: LocalizedStringResource {
        switch self {
        case .active: "Active"
        case .givenAway: "Given away"
        case .died: "Died"
        }
    }

    var isArchived: Bool { self != .active }
}

/// Kinds of dated care events stored as `PlantEvent`.
/// Pest infestations are modelled separately as `PestInfestation` because they span a date range.
nonisolated enum EventKind: String, Codable, CaseIterable, Sendable {
    case watering
    case fertilizing
    case repotting
    case cutting
    case newLeaf

    var title: LocalizedStringResource {
        switch self {
        case .watering: "Watering"
        case .fertilizing: "Fertilizing"
        case .repotting: "Repotting"
        case .cutting: "Cutting"
        case .newLeaf: "New leaf"
        }
    }

    var symbolName: String {
        switch self {
        case .watering: "drop.fill"
        case .fertilizing: "flask"
        case .repotting: "square.stack.3d.up"
        case .cutting: "scissors"
        case .newLeaf: "leaf"
        }
    }
}

/// How a plant was watered.
nonisolated enum WateringKind: String, Codable, CaseIterable, Sendable {
    /// Soil soaked thoroughly.
    case soaked
    /// Soil just moistened.
    case wet
    /// Plant showered.
    case shower

    var title: LocalizedStringResource {
        switch self {
        case .soaked: "Soaked"
        case .wet: "Moistened"
        case .shower: "Shower"
        }
    }

    var symbolName: String {
        switch self {
        case .soaked: "drop.fill"
        case .wet: "drop"
        case .shower: "shower"
        }
    }

    /// Priority used when several waterings happen on the same day (higher wins).
    var priority: Int {
        switch self {
        case .soaked: 3
        case .shower: 2
        case .wet: 1
        }
    }
}

/// Predefined pest types. `other` uses `PestInfestation.customPestName`.
nonisolated enum PestType: String, Codable, CaseIterable, Sendable {
    case spiderMites
    case thrips
    case fungusGnats
    case mealybugs
    case scale
    case aphids
    case whitefly
    case other

    var title: LocalizedStringResource {
        switch self {
        case .spiderMites: "Spider mites"
        case .thrips: "Thrips"
        case .fungusGnats: "Fungus gnats"
        case .mealybugs: "Mealybugs"
        case .scale: "Scale insects"
        case .aphids: "Aphids"
        case .whitefly: "Whitefly"
        case .other: "Other"
        }
    }
}
