import Foundation
import SwiftData

/// Result of an import, shown to the user afterwards.
struct ImportSummary: Equatable, Sendable {
    struct CodeChange: Equatable, Sendable {
        let plantName: String
        let oldCode: String
        let newCode: String
    }

    var plantsAdded = 0
    var plantsUpdated = 0
    var eventsAdded = 0
    var infestationsAdded = 0
    var photosAdded = 0
    var codeChanges: [CodeChange] = []

    var isEmpty: Bool {
        plantsAdded == 0 && plantsUpdated == 0 && eventsAdded == 0 && infestationsAdded == 0 && photosAdded == 0
    }
}

/// Reads `.blattify` backups and merges them into the store without creating duplicates.
enum BackupImporter {
    enum ImportError: LocalizedError, Equatable {
        case unreadableArchive
        case newerFormat(Int)
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .unreadableArchive:
                String(localized: "The file is not a valid Blattify backup.")
            case .newerFormat:
                String(localized: "This backup was created by a newer version of Blattify. Please update the app first.")
            case .invalidFormat:
                String(localized: "The backup has an unknown format.")
            }
        }
    }

    // MARK: - Reading

    /// Unpacks the archive, decodes `data.json` and loads the referenced images.
    @concurrent
    static func readArchive(at url: URL) async throws -> BackupSnapshot {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appending(path: "BlattifyImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        do {
            try BackupArchive.extract(file: url, to: staging)
        } catch {
            throw ImportError.unreadableArchive
        }

        let backup: BackupDTO
        do {
            let json = try Data(contentsOf: staging.appending(path: BackupCoding.dataFileName))
            backup = try BackupCoding.makeDecoder().decode(BackupDTO.self, from: json)
        } catch {
            throw ImportError.unreadableArchive
        }
        try validate(backup)

        let referencedPaths = backup.plants.flatMap { plant in
            [plant.profilePhotoFile].compactMap(\.self)
                + plant.events.flatMap { $0.photos.map(\.file) }
                + plant.infestations.flatMap { $0.photos.map(\.file) }
        }
        var files: [String: Data] = [:]
        for path in Set(referencedPaths) where BackupCoding.isValidImagePath(path) {
            // Missing images are tolerated; the entry is imported without that photo.
            files[path] = try? Data(contentsOf: staging.appending(path: path))
        }
        return BackupSnapshot(backup: backup, files: files)
    }

    nonisolated static func validate(_ backup: BackupDTO) throws {
        guard backup.formatVersion >= 1 else { throw ImportError.invalidFormat }
        guard backup.formatVersion <= BackupDTO.currentFormatVersion else {
            throw ImportError.newerFormat(backup.formatVersion)
        }
    }

    // MARK: - Merging

    /// Merge rules:
    /// 1. Plants are matched by `id`, then by `code` (each local plant matches at most one imported plant),
    ///    otherwise inserted.
    /// 2. For matched plants local values win; only empty/`nil` local fields are filled.
    /// 3. Events, infestations and photos are matched by `id`; missing ones are added, existing ones untouched.
    /// 4. Parent relations are resolved after all plants (only where the local plant has no parent).
    /// 5. A new plant whose code is already used (or retired) gets a newly generated code.
    static func merge(_ snapshot: BackupSnapshot, into context: ModelContext) throws -> ImportSummary {
        try validate(snapshot.backup)
        var summary = ImportSummary()

        let localPlants = try context.fetch(FetchDescriptor<Plant>())
        let localByID = Dictionary(localPlants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localByCode = Dictionary(localPlants.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var usedCodes = try context.usedPlantCodes()
        var events = Dictionary(try context.fetch(FetchDescriptor<PlantEvent>()).map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        var infestations = Dictionary(try context.fetch(FetchDescriptor<PestInfestation>()).map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        var photoIDs = Set(try context.fetch(FetchDescriptor<EventPhoto>()).map(\.id))

        // 1. Resolve every imported plant to a local plant (matched or new).
        var resolved: [UUID: Plant] = [:]
        var matchedLocalIDs = Set<UUID>()
        var newPlantIDs = Set<UUID>()
        for dto in snapshot.backup.plants {
            if let local = localByID[dto.id] {
                resolved[dto.id] = local
                matchedLocalIDs.insert(local.id)
            }
        }
        for dto in snapshot.backup.plants where resolved[dto.id] == nil {
            if let local = localByCode[dto.code], !matchedLocalIDs.contains(local.id) {
                resolved[dto.id] = local
                matchedLocalIDs.insert(local.id)
                continue
            }
            var code = dto.code
            if PlantCode.normalize(code) != code || usedCodes.contains(code) {
                code = try PlantCode.generate(excluding: usedCodes).rawValue
                summary.codeChanges.append(.init(plantName: dto.name, oldCode: dto.code, newCode: code))
            }
            usedCodes.insert(code)
            let plant = Plant(id: dto.id, code: code, name: dto.name, createdAt: dto.createdAt)
            context.insert(plant)
            apply(dto, to: plant, files: snapshot.files)
            resolved[dto.id] = plant
            newPlantIDs.insert(dto.id)
            summary.plantsAdded += 1
        }

        // 2.–3. Fill empty fields of matched plants and add missing children.
        var updatedLocalIDs = Set<UUID>()
        for dto in snapshot.backup.plants {
            guard let plant = resolved[dto.id] else { continue }
            let isNew = newPlantIDs.contains(dto.id)
            var changed = !isNew && fillEmptyFields(of: plant, from: dto, files: snapshot.files)

            for eventDTO in dto.events {
                let event: PlantEvent
                if let existing = events[eventDTO.id] {
                    event = existing
                } else {
                    event = makeEvent(from: eventDTO)
                    context.insert(event)
                    event.plant = plant
                    events[eventDTO.id] = event
                    summary.eventsAdded += 1
                    changed = true
                }
                let added = addMissingPhotos(eventDTO.photos, files: snapshot.files, knownIDs: &photoIDs, in: context) {
                    $0.event = event
                }
                summary.photosAdded += added
                changed = changed || added > 0
            }

            for infestationDTO in dto.infestations {
                let infestation: PestInfestation
                if let existing = infestations[infestationDTO.id] {
                    infestation = existing
                } else {
                    infestation = makeInfestation(from: infestationDTO)
                    context.insert(infestation)
                    infestation.plant = plant
                    infestations[infestationDTO.id] = infestation
                    summary.infestationsAdded += 1
                    changed = true
                }
                let added = addMissingPhotos(infestationDTO.photos, files: snapshot.files, knownIDs: &photoIDs, in: context) {
                    $0.infestation = infestation
                }
                summary.photosAdded += added
                changed = changed || added > 0
            }

            if changed && !isNew {
                updatedLocalIDs.insert(plant.id)
            }
        }

        // 4. Parents, after all plants exist.
        for dto in snapshot.backup.plants {
            guard let parentID = dto.parentID,
                  let plant = resolved[dto.id], plant.parent == nil,
                  let parent = resolved[parentID] ?? localByID[parentID],
                  !parent.isSelfOrDescendant(of: plant) else { continue }
            plant.parent = parent
            if !newPlantIDs.contains(dto.id) {
                updatedLocalIDs.insert(plant.id)
            }
        }
        summary.plantsUpdated = updatedLocalIDs.count

        // Keep codes of plants deleted elsewhere blocked.
        let retired = Set(try context.fetch(FetchDescriptor<RetiredPlantCode>()).map(\.code))
        for code in Set(snapshot.backup.retiredCodes ?? []) where !retired.contains(code) {
            context.insert(RetiredPlantCode(code: code))
        }

        try context.save()
        return summary
    }

    /// Copies all fields of a new plant from the DTO.
    private static func apply(_ dto: PlantDTO, to plant: Plant, files: [String: Data]) {
        plant.species = dto.species
        plant.acquiredDate = dto.acquiredDate
        plant.notes = dto.notes
        plant.statusRaw = dto.status
        plant.statusDate = dto.statusDate
        plant.wateringIntervalDays = dto.wateringIntervalDays
        plant.profilePhoto = dto.profilePhotoFile.flatMap { files[$0] }
    }

    /// Fills only empty local fields. Returns `true` if anything changed.
    private static func fillEmptyFields(of plant: Plant, from dto: PlantDTO, files: [String: Data]) -> Bool {
        var changed = false
        if plant.name.isEmpty, !dto.name.isEmpty {
            plant.name = dto.name
            changed = true
        }
        if plant.species.isEmpty, !dto.species.isEmpty {
            plant.species = dto.species
            changed = true
        }
        if plant.notes.isEmpty, !dto.notes.isEmpty {
            plant.notes = dto.notes
            changed = true
        }
        if plant.acquiredDate == nil, let acquired = dto.acquiredDate {
            plant.acquiredDate = acquired
            changed = true
        }
        if plant.wateringIntervalDays == nil, let interval = dto.wateringIntervalDays {
            plant.wateringIntervalDays = interval
            changed = true
        }
        if plant.profilePhoto == nil, let data = dto.profilePhotoFile.flatMap({ files[$0] }) {
            plant.profilePhoto = data
            changed = true
        }
        return changed
    }

    private static func makeEvent(from dto: EventDTO) -> PlantEvent {
        let event = PlantEvent(id: dto.id, kind: .watering, date: dto.date, note: dto.note)
        // Keep the raw kind so kinds from newer versions are preserved.
        event.kindRaw = dto.kind
        event.wateringKindRaw = dto.wateringKind
        event.fertilizerName = dto.fertilizerName
        event.fertilizerAmount = dto.fertilizerAmount
        event.potDiameterCm = dto.potDiameterCm
        event.substrate = dto.substrate
        event.resultingPlantID = dto.resultingPlantID
        return event
    }

    private static func makeInfestation(from dto: InfestationDTO) -> PestInfestation {
        let infestation = PestInfestation(
            id: dto.id,
            pestType: .other,
            customPestName: dto.customPestName,
            startDate: dto.startDate,
            resolvedDate: dto.resolvedDate,
            notes: dto.notes
        )
        infestation.pestTypeRaw = dto.pestType
        return infestation
    }

    /// Adds photos whose `id` is unknown and whose image file is present. Returns the number added.
    private static func addMissingPhotos(
        _ dtos: [PhotoDTO],
        files: [String: Data],
        knownIDs: inout Set<UUID>,
        in context: ModelContext,
        attach: (EventPhoto) -> Void
    ) -> Int {
        var added = 0
        for dto in dtos where !knownIDs.contains(dto.id) {
            guard let data = files[dto.file] else { continue }
            let photo = EventPhoto(id: dto.id, imageData: data, createdAt: dto.createdAt)
            context.insert(photo)
            attach(photo)
            knownIDs.insert(dto.id)
            added += 1
        }
        return added
    }
}
