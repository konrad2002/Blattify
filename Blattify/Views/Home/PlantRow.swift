import SwiftUI
import SwiftData

/// List row on the home screen.
struct PlantRow: View {
    let plant: Plant

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Code and last watering side by side; stacked at accessibility text sizes.
    private var detailLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        HStack(spacing: 12) {
            PlantPhotoView(data: plant.profilePhoto, pointSize: 56)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                if !plant.species.isEmpty {
                    Text(plant.species)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                detailLayout {
                    CodeChip(code: plant.code)
                    LastWateredLabel(plant: plant)
                }
            }

            Spacer(minLength: 0)

            PlantStateIcons(plant: plant)
        }
        .padding(.vertical, 2)
    }
}

/// Grid tile on the home screen.
struct PlantCard: View {
    let plant: Plant

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlantPhotoView(data: plant.profilePhoto, pointSize: 160, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    PlantStateIcons(plant: plant)
                        .padding(6)
                        .background(.regularMaterial, in: .capsule)
                        .padding(8)
                        .opacity(plant.isWateringDue() || plant.hasActiveInfestation ? 1 : 0)
                }

            Text(plant.name)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                CodeChip(code: plant.code)
                LastWateredLabel(plant: plant)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "💧 3 days ago" or "Never watered".
struct LastWateredLabel: View {
    let plant: Plant

    var body: some View {
        Group {
            if let date = plant.lastWatering?.date {
                Label {
                    Text(RelativeDay.text(for: date))
                } icon: {
                    Image(systemName: "drop")
                }
                .accessibilityLabel(Text("Last watered: \(Text(RelativeDay.text(for: date)))"))
            } else {
                Text("Never watered")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Watering-due and pest icons.
struct PlantStateIcons: View {
    let plant: Plant

    var body: some View {
        HStack(spacing: 6) {
            if plant.isWateringDue() {
                WateringDueBadge()
            }
            if plant.hasActiveInfestation {
                PestBadge()
            }
        }
        .font(.body)
    }
}

#Preview {
    let container = SampleData.makePreviewContainer()
    let plants = (try? container.mainContext.fetch(FetchDescriptor<Plant>())) ?? []
    List(plants) { plant in
        PlantRow(plant: plant)
    }
    .modelContainer(container)
}
