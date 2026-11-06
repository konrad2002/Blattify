import Foundation
import SwiftData

nonisolated enum BlattifySchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Plant.self, PlantEvent.self, PestInfestation.self, EventPhoto.self, RetiredPlantCode.self]
    }
}

nonisolated enum BlattifyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BlattifySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Creates the app's `ModelContainer`.
enum Persistence {
    static let cloudKitContainerIdentifier = "iCloud.com.konradweiss.Blattify"

    /// - Parameter inMemory: Use an in-memory store without CloudKit (previews and tests).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: BlattifySchemaV1.self)
        let configuration = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudKitContainerIdentifier))
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: BlattifyMigrationPlan.self,
            configurations: configuration
        )
    }
}
