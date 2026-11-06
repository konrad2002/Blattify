import SwiftUI
import SwiftData

/// Request to show the infestation form for a new (`infestation == nil`) or existing episode.
struct InfestationFormRequest: Identifiable {
    let id = UUID()
    var infestation: PestInfestation?
    /// Preset start date for new episodes (e.g. a day tapped in the activity matrix).
    var startDate: Date?
}

/// Create or edit a pest infestation episode.
struct InfestationFormView: View {
    let plant: Plant
    let infestation: PestInfestation?
    var initialStartDate: Date?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pestType = PestType.spiderMites
    @State private var customPestName = ""
    @State private var startDate = Date.now
    @State private var isResolved = false
    @State private var resolvedDate = Date.now
    @State private var notes = ""
    @State private var photos: [DraftPhoto] = []
    @State private var isProcessingPhotos = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var isNew: Bool { infestation == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pest", selection: $pestType) {
                        ForEach(PestType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    if pestType == .other {
                        TextField("Name of the pest", text: $customPestName)
                    }
                }

                Section {
                    DatePicker("Noticed on", selection: $startDate, in: ...Date.now, displayedComponents: .date)
                    Toggle("Resolved", isOn: $isResolved.animation())
                    if isResolved {
                        DatePicker("Resolved on", selection: $resolvedDate, in: startDate...Date.now,
                                   displayedComponents: .date)
                    }
                }

                Section {
                    TextField("Treatments and observations", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Notes")
                }

                PhotoDraftSection(photos: $photos, isProcessing: $isProcessingPhotos, errorMessage: $errorMessage)
            }
            .navigationTitle(isNew ? "Pest infestation" : "Edit infestation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isProcessingPhotos)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .onChange(of: startDate) { _, newStart in
                if resolvedDate < newStart {
                    resolvedDate = newStart
                }
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
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let infestation {
            pestType = infestation.pestType
            customPestName = infestation.customPestName ?? ""
            startDate = infestation.startDate
            isResolved = infestation.resolvedDate != nil
            resolvedDate = infestation.resolvedDate ?? .now
            notes = infestation.notes
            photos = DraftPhoto.drafts(from: infestation.photos)
        } else {
            startDate = min(initialStartDate ?? .now, .now)
        }
    }

    private func save() {
        let target: PestInfestation
        if let infestation {
            target = infestation
        } else {
            target = PestInfestation(pestType: pestType)
            modelContext.insert(target)
            target.plant = plant
        }
        target.pestType = pestType
        target.customPestName = pestType == .other ? customPestName.nonEmptyTrimmed : nil
        target.startDate = startDate
        target.resolvedDate = isResolved ? max(resolvedDate, startDate) : nil
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.apply(photos, replacing: target.photos) { $0.infestation = target }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    InfestationFormView(plant: Plant(code: "AB-23", name: "Preview"), infestation: nil)
        .modelContainer(SampleData.makePreviewContainer())
}
