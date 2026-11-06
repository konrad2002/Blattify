import SwiftUI
import SwiftData

/// Plant profile. Matrix, history, pests and family sections follow in later phases.
struct PlantDetailView: View {
    let plant: Plant

    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                PlantHeader(plant: plant)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            KeyFactsSection(plant: plant)

            if !plant.notes.isEmpty {
                Section("Notes") {
                    Text(plant.notes)
                }
            }
        }
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            PlantFormView(plant: plant)
        }
    }
}

/// Photo, name, species, code and state badges.
private struct PlantHeader: View {
    let plant: Plant

    var body: some View {
        VStack(spacing: 12) {
            PlantPhotoView(data: plant.profilePhoto, pointSize: 220, cornerRadius: 24)
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            VStack(spacing: 4) {
                Text(plant.name)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                if !plant.species.isEmpty {
                    Text(plant.species)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 8) {
                CodeChip(code: plant.code, font: .subheadline)
                if plant.isArchived {
                    StatusBadge(status: plant.status)
                }
                if plant.hasActiveInfestation {
                    Label("Pests", systemImage: "ladybug.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.15), in: .capsule)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Last care dates and general information.
private struct KeyFactsSection: View {
    let plant: Plant

    var body: some View {
        Section("Overview") {
            LabeledContent {
                if let watering = plant.lastWatering {
                    VStack(alignment: .trailing) {
                        Text(RelativeDay.text(for: watering.date))
                        if let kind = watering.wateringKind {
                            Text(kind.title)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Never")
                }
            } label: {
                Label("Last watered", systemImage: "drop.fill")
            }

            if let next = plant.nextWateringDate() {
                LabeledContent {
                    Text(RelativeDay.dueText(for: next))
                        .foregroundStyle(plant.isWateringDue() ? .red : .secondary)
                        .fontWeight(plant.isWateringDue() ? .semibold : .regular)
                } label: {
                    Label("Next watering", systemImage: "bell")
                }
            }

            LabeledContent {
                if let fertilizing = plant.lastFertilizing {
                    VStack(alignment: .trailing) {
                        Text(RelativeDay.text(for: fertilizing.date))
                        if let name = fertilizing.fertilizerName, !name.isEmpty {
                            Text(name)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Never")
                }
            } label: {
                Label("Last fertilized", systemImage: EventKind.fertilizing.symbolName)
            }

            LabeledContent {
                if let repotting = plant.lastRepotting {
                    VStack(alignment: .trailing) {
                        Text(RelativeDay.text(for: repotting.date))
                        if let diameter = repotting.potDiameterCm {
                            Text(Measurement(value: diameter, unit: UnitLength.centimeters),
                                 format: .measurement(width: .abbreviated))
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Never")
                }
            } label: {
                Label("Last repotted", systemImage: EventKind.repotting.symbolName)
            }

            LabeledContent {
                if let leaf = plant.lastNewLeaf {
                    Text(RelativeDay.text(for: leaf.date))
                } else {
                    Text("Never")
                }
            } label: {
                Label("Latest new leaf", systemImage: EventKind.newLeaf.symbolName)
            }

            if let acquired = plant.acquiredDate {
                LabeledContent {
                    Text(acquired, format: .dateTime.day().month().year())
                } label: {
                    Label("Bought on", systemImage: "cart")
                }
            }

            LabeledContent {
                Text(ageText)
            } label: {
                Label("With you for", systemImage: "calendar")
            }
        }
    }

    /// Time since purchase (or creation if the purchase date is unknown).
    private var ageText: String {
        let now = Date.now
        let start = min(plant.acquiredDate ?? plant.createdAt, now)
        let days = RelativeDay.days(from: start, to: now)
        let fields: Set<Date.ComponentsFormatStyle.Field> = days < 31 ? [.day] : [.year, .month]
        return (start..<now).formatted(.components(style: .wide, fields: fields))
    }
}

#Preview {
    let container = SampleData.makePreviewContainer()
    let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.code == "CA-9X" })
    let plant = (try? container.mainContext.fetch(descriptor).first) ?? Plant(code: "AB-23", name: "Preview")
    NavigationStack {
        PlantDetailView(plant: plant)
    }
    .modelContainer(container)
}
