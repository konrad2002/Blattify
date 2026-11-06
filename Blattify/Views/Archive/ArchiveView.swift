import SwiftUI
import SwiftData

/// Plants that were given away or died, grouped by status.
struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plants: [Plant]
    @State private var errorMessage: String?

    init() {
        let active = PlantStatus.active.rawValue
        _plants = Query(filter: #Predicate<Plant> { $0.statusRaw != active }, sort: \Plant.name)
    }

    var body: some View {
        List {
            ForEach([PlantStatus.givenAway, .died], id: \.self) { status in
                let group = plants.filter { $0.status == status }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { plant in
                            NavigationLink(value: Route.plant(plant)) {
                                ArchiveRow(plant: plant)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    restore(plant)
                                }
                                .tint(.green)
                            }
                        }
                    } header: {
                        Text(status.title)
                    }
                }
            }
        }
        .overlay {
            if plants.isEmpty {
                ContentUnavailableView {
                    Label("Archive is empty", systemImage: "archivebox")
                } description: {
                    Text("Plants you give away or that die appear here.")
                }
            }
        }
        .navigationTitle("Archive")
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private func restore(_ plant: Plant) {
        plant.restore()
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ArchiveRow: View {
    let plant: Plant

    var body: some View {
        HStack(spacing: 12) {
            PlantPhotoView(data: plant.profilePhoto, pointSize: 48)
                .frame(width: 48, height: 48)
                .saturation(0.3)
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                HStack(spacing: 8) {
                    CodeChip(code: plant.code)
                    if let date = plant.statusDate {
                        Text(date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ArchiveView()
    }
    .modelContainer(SampleData.makePreviewContainer())
}
