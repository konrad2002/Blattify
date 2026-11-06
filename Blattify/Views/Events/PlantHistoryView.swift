import SwiftUI
import SwiftData

/// All care events of a plant, grouped by month, filterable by kind.
struct PlantHistoryView: View {
    let plant: Plant

    @Environment(\.modelContext) private var modelContext
    @State private var filter: EventKind?
    @State private var editRequest: EventFormRequest?
    @State private var errorMessage: String?

    var body: some View {
        let sections = monthSections
        List {
            ForEach(sections, id: \.month) { section in
                Section {
                    ForEach(section.events) { event in
                        Button {
                            edit(event)
                        } label: {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                delete(event)
                            }
                            Button("Edit", systemImage: "pencil") {
                                edit(event)
                            }
                        }
                    }
                } header: {
                    Text(section.month, format: .dateTime.month(.wide).year())
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label("No entries", systemImage: "calendar")
                } description: {
                    Text("Logged care events appear here.")
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        Text("All entries").tag(EventKind?.none)
                        ForEach(EventKind.allCases, id: \.self) { kind in
                            Label {
                                Text(kind.title)
                            } icon: {
                                Image(systemName: kind.symbolName)
                            }
                            .tag(Optional(kind))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(item: $editRequest) { request in
            EventFormView(plant: plant, kind: request.kind, event: request.event)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var monthSections: [(month: Date, events: [PlantEvent])] {
        let calendar = Calendar.current
        let events = (plant.events ?? [])
            .filter { filter == nil || $0.kind == filter }
            .sorted { $0.date > $1.date }
        let grouped = Dictionary(grouping: events) { event in
            calendar.dateInterval(of: .month, for: event.date)?.start ?? event.date
        }
        return grouped
            .map { (month: $0.key, events: $0.value) }
            .sorted { $0.month > $1.month }
    }

    private func edit(_ event: PlantEvent) {
        guard let kind = event.kind else { return }
        editRequest = EventFormRequest(kind: kind, event: event)
    }

    private func delete(_ event: PlantEvent) {
        modelContext.delete(event)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container = SampleData.makePreviewContainer()
    let descriptor = FetchDescriptor<Plant>(predicate: #Predicate { $0.code == "MN-24" })
    let plant = (try? container.mainContext.fetch(descriptor).first) ?? Plant(code: "AB-23", name: "Preview")
    NavigationStack {
        PlantHistoryView(plant: plant)
    }
    .modelContainer(container)
}
