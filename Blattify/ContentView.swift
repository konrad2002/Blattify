import SwiftUI
import SwiftData

/// Root view: navigation stack with the home list.
struct ContentView: View {
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            PlantListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .plant(let plant):
                        PlantDetailView(plant: plant)
                    }
                }
        }
        .environment(router)
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.makePreviewContainer())
}
