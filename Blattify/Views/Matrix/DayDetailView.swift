import SwiftUI
import SwiftData

/// Events and pest episodes of a single day, with an option to add an event on that day.
struct DayDetailView: View {
    let plant: Plant
    /// Start of the day.
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @State private var formRequest: EventFormRequest?
    @State private var infestationRequest: InfestationFormRequest?

    var body: some View {
        NavigationStack {
            List {
                if dayEvents.isEmpty && dayInfestations.isEmpty {
                    Text("Nothing logged on this day.")
                        .foregroundStyle(.secondary)
                }
                if !dayEvents.isEmpty {
                    Section("Entries") {
                        ForEach(dayEvents) { event in
                            Button {
                                if let kind = event.kind {
                                    formRequest = EventFormRequest(kind: kind, event: event)
                                }
                            } label: {
                                EventRow(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !dayInfestations.isEmpty {
                    Section("Pests") {
                        ForEach(dayInfestations) { infestation in
                            Button {
                                infestationRequest = InfestationFormRequest(infestation: infestation)
                            } label: {
                                InfestationRow(infestation: infestation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(Text(date, format: .dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
            .sheet(item: $formRequest) { request in
                EventFormView(plant: plant, kind: request.kind, event: request.event, initialDate: request.date)
            }
            .sheet(item: $infestationRequest) { request in
                InfestationFormView(plant: plant, infestation: request.infestation,
                                    initialStartDate: request.startDate)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var addMenu: some View {
        Menu {
            ForEach(EventKind.allCases, id: \.self) { kind in
                Button {
                    formRequest = EventFormRequest(kind: kind, date: presetDate)
                } label: {
                    Label {
                        Text(kind.title)
                    } icon: {
                        Image(systemName: kind.symbolName)
                    }
                }
            }
            Button {
                infestationRequest = InfestationFormRequest(startDate: presetDate)
            } label: {
                Label("Pest infestation", systemImage: "ladybug")
            }
        } label: {
            Label("Add event on this day", systemImage: "plus")
        }
    }

    private var dayEvents: [PlantEvent] {
        (plant.events ?? [])
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    /// Infestations whose range includes this day.
    private var dayInfestations: [PestInfestation] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return (plant.infestations ?? []).filter { infestation in
            calendar.startOfDay(for: infestation.startDate) <= dayStart
                && (infestation.resolvedDate.map { calendar.startOfDay(for: $0) >= dayStart } ?? true)
        }
    }

    /// The selected day with the current time of day, but never in the future.
    private var presetDate: Date {
        let calendar = Calendar.current
        let now = Date.now
        let time = calendar.dateComponents([.hour, .minute], from: now)
        let combined = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: date) ?? date
        return min(combined, now)
    }
}
