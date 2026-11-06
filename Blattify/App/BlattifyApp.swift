import SwiftUI
import SwiftData

@main
struct BlattifyApp: App {
    /// `nil` if the persistent store could not be opened; the error is shown instead of crashing.
    private let modelContainer: ModelContainer?
    private let storeError: Error?

    init() {
        do {
            modelContainer = try Persistence.makeContainer()
            storeError = nil
        } catch {
            modelContainer = nil
            storeError = error
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .modelContainer(modelContainer)
            } else {
                ContentUnavailableView(
                    "Data could not be loaded",
                    systemImage: "exclamationmark.triangle",
                    description: Text(storeError?.localizedDescription ?? "")
                )
            }
        }
    }
}
