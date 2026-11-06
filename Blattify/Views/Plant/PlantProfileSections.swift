import SwiftUI

/// Photo, name, species, code and state badges.
struct PlantHeader: View {
    let plant: Plant
    let showLabel: () -> Void

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
                Button(action: showLabel) {
                    CodeChip(code: plant.code, font: .subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows the QR label"))
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

            if let date = plant.statusDate, let line = statusLine(for: plant.status, date: date) {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// `nil` for active plants.
    private func statusLine(for status: PlantStatus, date: Date) -> LocalizedStringKey? {
        let formatted = date.formatted(date: .long, time: .omitted)
        switch status {
        case .givenAway: return "Given away on \(formatted)"
        case .died: return "Died on \(formatted)"
        case .active: return nil
        }
    }
}

/// Last care dates and general information.
struct KeyFactsSection: View {
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

            if let next = plant.nextWateringDate(), !plant.isArchived {
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
                            Text(verbatim: PlantEvent.formattedPotDiameter(diameter))
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

/// Active and resolved pest infestations with actions.
struct PestSection: View {
    let plant: Plant
    let onAdd: () -> Void
    let onEdit: (PestInfestation) -> Void
    let onResolve: (PestInfestation) -> Void

    var body: some View {
        let all = plant.infestations ?? []
        let active = all.filter(\.isActive).sorted { $0.startDate > $1.startDate }
        let resolved = all.filter { !$0.isActive }.sorted { $0.startDate > $1.startDate }

        Section("Pests") {
            ForEach(active) { infestation in
                Button {
                    onEdit(infestation)
                } label: {
                    InfestationRow(infestation: infestation)
                }
                .buttonStyle(.plain)
                Button {
                    onResolve(infestation)
                } label: {
                    Label("Mark as resolved", systemImage: "checkmark.circle")
                }
            }
            ForEach(resolved) { infestation in
                Button {
                    onEdit(infestation)
                } label: {
                    InfestationRow(infestation: infestation)
                }
                .buttonStyle(.plain)
            }
            Button(action: onAdd) {
                Label("Log pest infestation", systemImage: "plus")
            }
        }
    }
}

/// Parent plant, this plant and its cuttings as a small tree.
struct FamilySection: View {
    let plant: Plant

    var body: some View {
        let children = plant.sortedChildren
        if plant.parent != nil || !children.isEmpty {
            Section("Family") {
                if let parent = plant.parent {
                    NavigationLink(value: Route.plant(parent)) {
                        FamilyRow(plant: parent, role: "Parent plant", level: 0)
                    }
                }
                FamilyRow(plant: plant, role: "This plant", level: plant.parent == nil ? 0 : 1)
                ForEach(children) { child in
                    NavigationLink(value: Route.plant(child)) {
                        FamilyRow(plant: child, role: "Cutting", level: plant.parent == nil ? 1 : 2)
                    }
                }
            }
        }
    }
}

private struct FamilyRow: View {
    let plant: Plant
    let role: LocalizedStringKey
    /// Indentation level in the tree (0 = top).
    let level: Int

    var body: some View {
        HStack(spacing: 10) {
            if level > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .padding(.leading, CGFloat(level - 1) * 20)
                    .accessibilityHidden(true)
            }
            PlantPhotoView(data: plant.profilePhoto, pointSize: 36, cornerRadius: 8)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(plant.name)
                    .font(.subheadline.weight(.semibold))
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if plant.isArchived {
                StatusBadge(status: plant.status)
            }
        }
        // Archived relatives stay visible but greyed out.
        .opacity(plant.isArchived ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}
