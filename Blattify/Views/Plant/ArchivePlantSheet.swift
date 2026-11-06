import SwiftUI
import SwiftData

/// Marks a plant as given away or died.
struct ArchivePlantSheet: View {
    let plant: Plant

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var status = PlantStatus.givenAway
    @State private var date = Date.now
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Status", selection: $status) {
                        Text(PlantStatus.givenAway.title).tag(PlantStatus.givenAway)
                        Text(PlantStatus.died.title).tag(PlantStatus.died)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Archived plants are hidden from the plant list but stay in the archive and in family trees. You can restore them at any time.")
                }
            }
            .navigationTitle("Archive plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Archive", action: save)
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        plant.archive(as: status, on: date)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
