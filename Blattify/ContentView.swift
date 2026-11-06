import SwiftUI
import SwiftData

/// Temporary root view until the plant list is implemented (Phase 2).
struct ContentView: View {
    @Query private var plants: [Plant]

    var body: some View {
        ContentUnavailableView(
            "Blattify",
            systemImage: "leaf",
            description: Text("^[\(plants.count) plant](inflect: true)")
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.makePreviewContainer())
}
