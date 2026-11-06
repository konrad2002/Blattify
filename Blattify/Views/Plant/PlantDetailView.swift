import SwiftUI
import SwiftData

/// Plant profile. Pests and family sections follow in Phase 6.
struct PlantDetailView: View {
    let plant: Plant

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var eventFormRequest: EventFormRequest?
    @State private var quickLogged: QuickLoggedEvent?
    @State private var errorMessage: String?

    /// Number of entries shown in the profile before "Show all".
    private static let recentHistoryLimit = 5

    var body: some View {
        List {
            Section {
                PlantHeader(plant: plant) {
                    router.labelPlant = plant
                }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                QuickActionsView(
                    onWater: { logQuickly(.watering, wateringKind: $0) },
                    onNewLeaf: { logQuickly(.newLeaf) },
                    onForm: { eventFormRequest = EventFormRequest(kind: $0) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            KeyFactsSection(plant: plant)

            Section("Activity") {
                ActivityMatrixView(plant: plant)
            }

            recentHistorySection

            if !plant.notes.isEmpty {
                Section("Notes") {
                    Text(plant.notes)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let quickLogged {
                UndoToast(title: quickLogged.title, systemImage: quickLogged.systemImage) {
                    undo(quickLogged)
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: quickLogged?.id)
        .task(id: quickLogged?.id) {
            // Hide the undo toast after a few seconds.
            guard quickLogged != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                quickLogged = nil
            }
        }
        .sensoryFeedback(.success, trigger: quickLogged?.id) { _, newValue in newValue != nil }
        .sheet(item: $eventFormRequest) { request in
            EventFormView(plant: plant, kind: request.kind, event: request.event, initialDate: request.date)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.labelPlant = plant
                } label: {
                    Label("QR label", systemImage: "qrcode")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            PlantFormView(plant: plant)
        }
    }

    @ViewBuilder
    private var recentHistorySection: some View {
        let events = (plant.events ?? []).sorted { $0.date > $1.date }
        Section("History") {
            if events.isEmpty {
                Text("Nothing logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(Self.recentHistoryLimit)) { event in
                    Button {
                        if let kind = event.kind {
                            eventFormRequest = EventFormRequest(kind: kind, event: event)
                        }
                    } label: {
                        EventRow(event: event)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: Route.history(plant)) {
                    Text("Show all entries (\(events.count))")
                }
            }
        }
    }

    /// Logs an event with the current date right away; the undo toast allows taking it back.
    private func logQuickly(_ kind: EventKind, wateringKind: WateringKind? = nil) {
        let event = PlantEvent(kind: kind, wateringKind: wateringKind)
        modelContext.insert(event)
        event.plant = plant
        do {
            try modelContext.save()
            quickLogged = QuickLoggedEvent(event: event)
        } catch {
            modelContext.delete(event)
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ logged: QuickLoggedEvent) {
        quickLogged = nil
        modelContext.delete(logged.event)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The last quickly logged event, shown in the undo toast.
private struct QuickLoggedEvent {
    let id = UUID()
    let event: PlantEvent

    var title: Text {
        if let wateringKind = event.wateringKind {
            Text("Watered: \(Text(wateringKind.title))")
        } else if let kind = event.kind {
            Text("\(Text(kind.title)) logged")
        } else {
            Text("Logged")
        }
    }

    var systemImage: String {
        event.wateringKind?.symbolName ?? event.kind?.symbolName ?? "checkmark"
    }
}

/// Prominent buttons for the most common care actions.
private struct QuickActionsView: View {
    let onWater: (WateringKind) -> Void
    let onNewLeaf: () -> Void
    let onForm: (EventKind) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(WateringKind.allCases, id: \.self) { kind in
                    Button {
                        onWater(kind)
                    } label: {
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.symbolName)
                        }
                    }
                }
                Divider()
                Button("With details…", systemImage: "square.and.pencil") { onForm(.watering) }
            } label: {
                QuickActionLabel(title: "Water", systemImage: "drop.fill", tint: EventKind.watering.tint)
            }

            Button {
                onForm(.fertilizing)
            } label: {
                QuickActionLabel(title: "Fertilize", systemImage: EventKind.fertilizing.symbolName,
                                 tint: EventKind.fertilizing.tint)
            }

            Button(action: onNewLeaf) {
                QuickActionLabel(title: "New leaf", systemImage: EventKind.newLeaf.symbolName,
                                 tint: EventKind.newLeaf.tint)
            }

            Menu {
                Button {
                    onForm(.repotting)
                } label: {
                    Label("Repotting", systemImage: EventKind.repotting.symbolName)
                }
                Button {
                    onForm(.cutting)
                } label: {
                    Label("Cutting", systemImage: EventKind.cutting.symbolName)
                }
                Button {
                    onForm(.newLeaf)
                } label: {
                    Label("New leaf with details…", systemImage: EventKind.newLeaf.symbolName)
                }
            } label: {
                QuickActionLabel(title: "More", systemImage: "ellipsis", tint: .secondary)
            }
        }
        .buttonStyle(.glass)
        .menuStyle(.button)
    }
}

private struct QuickActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                // Fixed height so short symbols (ellipsis) keep all buttons equally tall.
                .frame(height: 28)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Photo, name, species, code and state badges.
private struct PlantHeader: View {
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

#Preview {
    let container = SampleData.makePreviewContainer()
    let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.code == "CA-9X" })
    let plant = (try? container.mainContext.fetch(descriptor).first) ?? Plant(code: "AB-23", name: "Preview")
    NavigationStack {
        PlantDetailView(plant: plant)
    }
    .environment(AppRouter())
    .modelContainer(container)
}
