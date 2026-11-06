import Foundation
import Photos

/// Saves images to the photo library with add-only permission.
nonisolated enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            String(localized: "Blattify may not add photos. You can allow it in the Settings app.")
        }
    }

    /// Kept nonisolated so the change block is not main-actor isolated
    /// (Photos runs it on a background queue).
    static func savePNG(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}
