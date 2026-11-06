import Foundation
import SwiftData

/// A photo attached to either a care event or a pest infestation.
@Model
final class EventPhoto {
    var id: UUID = UUID()
    /// Downscaled JPEG data.
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date.now

    var event: PlantEvent?
    var infestation: PestInfestation?

    init(id: UUID = UUID(), imageData: Data?, createdAt: Date = .now) {
        self.id = id
        self.imageData = imageData
        self.createdAt = createdAt
    }
}
