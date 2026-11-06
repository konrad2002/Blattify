import SwiftUI
import SwiftData

/// Root view: navigation stack with the home list, app-wide sheets and deep-link handling.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationHandler.self) private var notificationHandler
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            PlantListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .plant(let plant):
                        PlantDetailView(plant: plant)
                    case .history(let plant):
                        PlantHistoryView(plant: plant)
                    case .archive:
                        ArchiveView()
                    case .settings:
                        SettingsView()
                    }
                }
        }
        .environment(router)
        .sheet(item: $router.newPlantRequest, onDismiss: router.newPlantSheetDismissed) { request in
            PlantFormView(plant: nil, presetCode: request.presetCode, cutting: request.cutting) { plant in
                router.didCreate(plant)
            }
        }
        .sheet(item: $router.labelPlant) { plant in
            QRLabelSheet(plant: plant)
        }
        .fullScreenCover(isPresented: $router.isScanning, onDismiss: {
            router.scannerDismissed(in: modelContext)
        }) {
            QRScannerView { code in
                router.didScan(code)
            }
        }
        .alert(
            "Unknown code",
            isPresented: Binding(get: { router.unknownCode != nil }, set: { if !$0 { router.unknownCode = nil } }),
            presenting: router.unknownCode
        ) { code in
            Button("Create plant") { router.createPlant(presetCode: code) }
            Button("Cancel", role: .cancel) {}
        } message: { code in
            Text("No plant with code \(code.rawValue)")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { router.errorMessage != nil }, set: { if !$0 { router.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.errorMessage ?? "")
        }
        .onOpenURL { url in
            router.handle(url, in: modelContext)
        }
        // `initial: true` also handles a tap that launched the app.
        .onChange(of: notificationHandler.pendingPlantID, initial: true) { _, plantID in
            guard let plantID else { return }
            router.open(plantID: plantID, in: modelContext)
            notificationHandler.pendingPlantID = nil
        }
    }
}

#Preview {
    let container = SampleData.makePreviewContainer()
    ContentView()
        .modelContainer(container)
        .environment(NotificationHandler())
        .environment(ReminderCoordinator(container: container))
}
