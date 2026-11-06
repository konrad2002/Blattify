import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// `.blattify` backup archive (declared as exported type in Info.plist).
    nonisolated static let blattifyBackup = UTType(exportedAs: "com.konradweiss.blattify.backup")
}

/// Root of `data.json` in a backup. Separate from the `@Model` classes so the file format stays stable.
nonisolated struct BackupDTO: Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var plants: [PlantDTO]
    /// Codes of permanently deleted plants, so they stay blocked after a restore.
    var retiredCodes: [String]?
}

nonisolated struct PlantDTO: Codable, Sendable {
    var id: UUID
    var code: String
    var name: String
    var species: String
    var acquiredDate: Date?
    var notes: String
    var status: String
    var statusDate: Date?
    var wateringIntervalDays: Int?
    var parentID: UUID?
    var profilePhotoFile: String?
    var createdAt: Date
    var events: [EventDTO]
    var infestations: [InfestationDTO]
}

nonisolated struct EventDTO: Codable, Sendable {
    var id: UUID
    var date: Date
    /// Raw value, kept as string so unknown kinds from newer versions survive a round trip.
    var kind: String
    var wateringKind: String?
    var fertilizerName: String?
    var fertilizerAmount: String?
    var potDiameterCm: Double?
    var substrate: String?
    var resultingPlantID: UUID?
    var note: String
    var photos: [PhotoDTO]
}

nonisolated struct InfestationDTO: Codable, Sendable {
    var id: UUID
    var pestType: String
    var customPestName: String?
    var startDate: Date
    var resolvedDate: Date?
    var notes: String
    var photos: [PhotoDTO]
}

nonisolated struct PhotoDTO: Codable, Sendable {
    var id: UUID
    /// Path inside the archive, e.g. `images/<id>.jpg`.
    var file: String
    var createdAt: Date
}

/// A backup in memory: the JSON content plus the image files it references (path → data).
nonisolated struct BackupSnapshot: Sendable {
    var backup: BackupDTO
    var files: [String: Data]
}

nonisolated enum BackupCoding {
    static let dataFileName = "data.json"
    static let imagesDirectory = "images"

    static func profilePhotoPath(for plantID: UUID) -> String {
        "\(imagesDirectory)/profile-\(plantID.uuidString).jpg"
    }

    static func photoPath(for photoID: UUID) -> String {
        "\(imagesDirectory)/\(photoID.uuidString).jpg"
    }

    /// Only `images/<letters, digits, dashes>.jpg` is accepted, so a manipulated backup
    /// cannot make the app read or write files outside the backup folder.
    static func isValidImagePath(_ path: String) -> Bool {
        path.wholeMatch(of: /images\/[A-Za-z0-9-]+\.jpg/) != nil
    }

    /// ISO 8601 in UTC with milliseconds, e.g. `2026-11-06T10:00:00.123Z`.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Also accept dates without fractional seconds.
            if let date = (try? dateStyle.parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }
}
