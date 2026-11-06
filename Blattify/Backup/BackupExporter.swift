import Foundation
import SwiftData

/// Creates `.blattify` backups: a snapshot is taken on the main actor, writing and compressing
/// happen in the background.
enum BackupExporter {
    /// e.g. `Blattify-Backup-2026-11-06.blattify`
    nonisolated static func fileName(for date: Date) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        return "Blattify-Backup-\(day).blattify"
    }

    /// Converts all plants (including archived ones) with their entries and photos into DTOs.
    static func makeSnapshot(from context: ModelContext, now: Date = .now) throws -> BackupSnapshot {
        var files: [String: Data] = [:]

        func photoDTOs(_ photos: [EventPhoto]?) -> [PhotoDTO] {
            (photos ?? []).sorted { $0.createdAt < $1.createdAt }.compactMap { photo in
                guard let data = photo.imageData else { return nil }
                let path = BackupCoding.photoPath(for: photo.id)
                files[path] = data
                return PhotoDTO(id: photo.id, file: path, createdAt: photo.createdAt)
            }
        }

        let plants = try context.fetch(FetchDescriptor<Plant>(sortBy: [SortDescriptor(\.createdAt)]))
        let plantDTOs = plants.map { plant -> PlantDTO in
            var profilePath: String?
            if let data = plant.profilePhoto {
                let path = BackupCoding.profilePhotoPath(for: plant.id)
                files[path] = data
                profilePath = path
            }
            let events = (plant.events ?? []).sorted { $0.date < $1.date }.map { event in
                EventDTO(
                    id: event.id,
                    date: event.date,
                    kind: event.kindRaw,
                    wateringKind: event.wateringKindRaw,
                    fertilizerName: event.fertilizerName,
                    fertilizerAmount: event.fertilizerAmount,
                    potDiameterCm: event.potDiameterCm,
                    substrate: event.substrate,
                    resultingPlantID: event.resultingPlantID,
                    note: event.note,
                    photos: photoDTOs(event.photos)
                )
            }
            let infestations = (plant.infestations ?? []).sorted { $0.startDate < $1.startDate }.map { infestation in
                InfestationDTO(
                    id: infestation.id,
                    pestType: infestation.pestTypeRaw,
                    customPestName: infestation.customPestName,
                    startDate: infestation.startDate,
                    resolvedDate: infestation.resolvedDate,
                    notes: infestation.notes,
                    photos: photoDTOs(infestation.photos)
                )
            }
            return PlantDTO(
                id: plant.id,
                code: plant.code,
                name: plant.name,
                species: plant.species,
                acquiredDate: plant.acquiredDate,
                notes: plant.notes,
                status: plant.statusRaw,
                statusDate: plant.statusDate,
                wateringIntervalDays: plant.wateringIntervalDays,
                parentID: plant.parent?.id,
                profilePhotoFile: profilePath,
                createdAt: plant.createdAt,
                events: events,
                infestations: infestations
            )
        }

        let retiredCodes = try context.fetch(FetchDescriptor<RetiredPlantCode>()).map(\.code).sorted()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let backup = BackupDTO(
            formatVersion: BackupDTO.currentFormatVersion,
            exportedAt: now,
            appVersion: appVersion,
            plants: plantDTOs,
            retiredCodes: retiredCodes
        )
        return BackupSnapshot(backup: backup, files: files)
    }

    /// Writes `data.json` and the images to a staging folder and packs it into a `.blattify` file
    /// inside `directory`. Returns the URL of the archive.
    @concurrent
    static func writeArchive(_ snapshot: BackupSnapshot, to directory: URL) async throws -> URL {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appending(path: "BlattifyExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.createDirectory(at: staging.appending(path: BackupCoding.imagesDirectory), withIntermediateDirectories: true)
        try BackupCoding.makeEncoder().encode(snapshot.backup).write(to: staging.appending(path: BackupCoding.dataFileName))
        for (path, data) in snapshot.files where BackupCoding.isValidImagePath(path) {
            try data.write(to: staging.appending(path: path))
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appending(path: fileName(for: snapshot.backup.exportedAt))
        if fileManager.fileExists(atPath: archive.path(percentEncoded: false)) {
            try fileManager.removeItem(at: archive)
        }
        try BackupArchive.compress(directory: staging, to: archive)
        return archive
    }
}
