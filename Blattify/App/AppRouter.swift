import SwiftUI
import SwiftData

/// Destinations in the main navigation stack.
enum Route: Hashable {
    case plant(Plant)
    case history(Plant)
    case archive
    case settings

    /// The plant shown by this route, if any.
    var plant: Plant? {
        switch self {
        case .plant(let plant), .history(let plant): plant
        case .archive, .settings: nil
        }
    }
}

/// The parent plant and cutting event a new plant is grown from.
struct CuttingSource {
    let parent: Plant
    let event: PlantEvent
}

/// Request to show the new-plant form, optionally with a code from a scanned label
/// or prefilled from a cutting.
struct NewPlantRequest: Identifiable {
    let id = UUID()
    var presetCode: PlantCode?
    var cutting: CuttingSource?
}

/// Owns navigation and app-wide presentations so plants can be opened from anywhere
/// (code entry, scanner, deep links) and the QR label can follow plant creation.
@Observable
final class AppRouter {
    var path: [Route] = []
    var newPlantRequest: NewPlantRequest?
    var labelPlant: Plant?
    var isScanning = false
    /// A scanned or linked code that belongs to no plant; shown as an alert.
    var unknownCode: PlantCode?
    /// Error from an app-wide action (e.g. deleting a plant after leaving its screen).
    var errorMessage: String?
    /// A backup file waiting for the user's confirmation to import.
    var importCandidate: URL?
    var isImporting = false
    var importSummary: ImportSummary?

    /// Plant created in the form; its QR label opens once the form sheet is dismissed.
    private var createdPlant: Plant?
    /// Code recognized by the scanner; handled once the scanner is dismissed.
    private var scannedCode: PlantCode?

    /// Shows the plant's profile as the only screen above the home list.
    func showPlant(_ plant: Plant) {
        path = [.plant(plant)]
    }

    func createPlant(presetCode: PlantCode? = nil) {
        newPlantRequest = NewPlantRequest(presetCode: presetCode)
    }

    /// Opens the new-plant form prefilled from a cutting of `parent`.
    func createPlant(fromCutting event: PlantEvent, of parent: Plant) {
        newPlantRequest = NewPlantRequest(cutting: CuttingSource(parent: parent, event: event))
    }

    /// Leaves all screens showing `plant`, then deletes it once the navigation animation is done
    /// (a view must not render a model that was already deleted).
    func deletePermanently(_ plant: Plant, in modelContext: ModelContext) {
        removeRoutes(for: plant)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            do {
                try modelContext.deletePermanently(plant)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Imports a backup: copies it out of the (possibly security-scoped) location, reads it in the
    /// background and merges it on the main actor. Shows a summary or an error afterwards.
    func importBackup(from url: URL, into modelContext: ModelContext) async {
        isImporting = true
        defer { isImporting = false }

        let fileManager = FileManager.default
        let copy = fileManager.temporaryDirectory.appending(path: "BlattifyImport-\(UUID().uuidString).blattify")
        defer { try? fileManager.removeItem(at: copy) }

        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            try fileManager.copyItem(at: url, to: copy)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            let snapshot = try await BackupImporter.readArchive(at: copy)
            importSummary = try BackupImporter.merge(snapshot, into: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes screens showing `plant` (before it is deleted).
    func removeRoutes(for plant: Plant) {
        path.removeAll { $0.plant == plant }
        if labelPlant == plant {
            labelPlant = nil
        }
    }

    /// Called by the form after saving a new plant.
    func didCreate(_ plant: Plant) {
        createdPlant = plant
        showPlant(plant)
    }

    /// Called when the new-plant sheet is gone; presenting the label earlier would be ignored.
    func newPlantSheetDismissed() {
        labelPlant = createdPlant
        createdPlant = nil
    }

    func didScan(_ code: PlantCode) {
        scannedCode = code
        isScanning = false
    }

    /// Called when the scanner cover is gone, so a possible "unknown code" alert can be shown.
    func scannerDismissed(in modelContext: ModelContext) {
        guard let code = scannedCode else { return }
        scannedCode = nil
        open(code, in: modelContext)
    }

    /// Opens the plant with `code`, or reports it as unknown.
    /// With several matches (sync collision) the oldest plant is opened.
    func open(_ code: PlantCode, in modelContext: ModelContext) {
        let matches = (try? modelContext.plants(withCode: code.rawValue)) ?? []
        if let plant = matches.min(by: { $0.createdAt < $1.createdAt }) {
            showPlant(plant)
        } else {
            unknownCode = code
        }
    }

    /// Opens the plant with `id` (e.g. from a tapped notification) and closes presentations.
    func open(plantID id: UUID, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.id == id })
        guard let plant = try? modelContext.fetch(descriptor).first else { return }
        isScanning = false
        labelPlant = nil
        newPlantRequest = nil
        showPlant(plant)
    }

    /// Handles `blattify://plant/XX-XX` links (e.g. from the system Camera app).
    func handle(_ url: URL, in modelContext: ModelContext) {
        // A .blattify file opened from Files, Mail or AirDrop.
        if url.isFileURL {
            if url.pathExtension.lowercased() == "blattify" {
                importCandidate = url
            }
            return
        }
        guard let code = PlantCode(url: url) else { return }
        // Close presentations so the plant becomes visible.
        isScanning = false
        labelPlant = nil
        newPlantRequest = nil
        open(code, in: modelContext)
    }
}
