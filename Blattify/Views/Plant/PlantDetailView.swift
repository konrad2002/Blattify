import SwiftUI
import SwiftData

/// Plant profile: header, quick actions, overview, activity, pests, family, history and notes.
struct PlantDetailView: View {
    let plant: Plant

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var isArchiving = false
    @State private var isConfirmingDelete = false
    @State private var eventFormRequest: EventFormRequest?
    @State private var infestationFormRequest: InfestationFormRequest?
    @State private var quickLogged: QuickLoggedEvent?
    /// A cutting event that was just created; offering to create a plant from it after the form closes.
    @State private var newCuttingEvent: PlantEvent?
    @State private var isOfferingCuttingPlant = false
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
                    onForm: { eventFormRequest = EventFormRequest(kind: $0) },
                    onPest: { infestationFormRequest = InfestationFormRequest() }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            KeyFactsSection(plant: plant)

            Section("Activity") {
                ActivityMatrixView(plant: plant)
            }

            PestSection(
                plant: plant,
                onAdd: { infestationFormRequest = InfestationFormRequest() },
                onEdit: { infestationFormRequest = InfestationFormRequest(infestation: $0) },
                onResolve: resolve
            )

            FamilySection(plant: plant)

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
        .sheet(item: $eventFormRequest, onDismiss: offerCuttingPlantIfNeeded) { request in
            EventFormView(plant: plant, kind: request.kind, event: request.event, initialDate: request.date) { event in
                if event.kind == .cutting {
                    newCuttingEvent = event
                }
            }
        }
        .sheet(item: $infestationFormRequest) { request in
            InfestationFormView(plant: plant, infestation: request.infestation, initialStartDate: request.startDate)
        }
        .sheet(isPresented: $isEditing) {
            PlantFormView(plant: plant)
        }
        .sheet(isPresented: $isArchiving) {
            ArchivePlantSheet(plant: plant)
        }
        .alert("Create a plant from this cutting?", isPresented: $isOfferingCuttingPlant, presenting: newCuttingEvent) { event in
            Button("Create plant") {
                router.createPlant(fromCutting: event, of: plant)
                newCuttingEvent = nil
            }
            Button("Not now", role: .cancel) {
                newCuttingEvent = nil
            }
        } message: { _ in
            Text("The new plant gets its own code and \(plant.name) as its parent plant.")
        }
        .confirmationDialog(
            Text("Delete \(plant.name)?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                router.deletePermanently(plant, in: modelContext)
            }
        } message: {
            deleteMessage
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .navigationTitle(plant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                router.labelPlant = plant
            } label: {
                Label("QR label", systemImage: "qrcode")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Edit", systemImage: "pencil") { isEditing = true }
                if plant.isArchived {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore() }
                } else {
                    Button("Archive…", systemImage: "archivebox") { isArchiving = true }
                }
                Divider()
                Button("Delete plant", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
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

    private var deleteMessage: Text {
        let entries = plant.events?.count ?? 0
        let pests = plant.infestations?.count ?? 0
        return Text("^[\(entries) entry](inflect: true) and ^[\(pests) pest record](inflect: true) will be deleted as well. Cuttings are kept. The code \(plant.code) will not be used again.")
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
        saveContext()
    }

    private func resolve(_ infestation: PestInfestation) {
        infestation.resolvedDate = .now
        saveContext()
    }

    private func restore() {
        plant.restore()
        saveContext()
    }

    /// Asks after the event form is gone; an alert presented while the sheet closes would be dropped.
    private func offerCuttingPlantIfNeeded() {
        if newCuttingEvent != nil {
            isOfferingCuttingPlant = true
        }
    }

    private func saveContext() {
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

#Preview {
    let container = SampleData.makePreviewContainer()
    let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.code == "MN-24" })
    let plant = (try? container.mainContext.fetch(descriptor).first) ?? Plant(code: "AB-23", name: "Preview")
    NavigationStack {
        PlantDetailView(plant: plant)
    }
    .environment(AppRouter())
    .modelContainer(container)
}
