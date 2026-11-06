import SwiftUI
import SwiftData
import PhotosUI

/// Create (`plant == nil`) or edit a plant.
struct PlantFormView: View {
    let plant: Plant?
    /// Code from a scanned label without a plant; used if it is still free.
    var presetCode: PlantCode? = nil
    /// Called after a new plant was inserted.
    var onCreate: (Plant) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Plant.name) private var allPlants: [Plant]

    @State private var code = ""
    @State private var name = ""
    @State private var species = ""
    @State private var hasAcquiredDate = false
    @State private var acquiredDate = Date.now
    @State private var parent: Plant?
    @State private var reminderEnabled = false
    @State private var wateringIntervalDays = 7
    @State private var notes = ""
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @FocusState private var isSpeciesFocused: Bool

    private var isNew: Bool { plant == nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !code.isEmpty && !isProcessingPhoto
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                detailsSection
                acquiredSection
                parentSection
                reminderSection
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isNew ? "New plant" : "Edit plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(from: item) }
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
    }

    // MARK: - Sections

    private var photoSection: some View {
        let hasPhoto = photoData != nil
        return Section {
            HStack(spacing: 16) {
                PlantPhotoView(data: photoData, pointSize: 88, cornerRadius: 16)
                    .frame(width: 88, height: 88)
                    .overlay {
                        if isProcessingPhoto {
                            ProgressView()
                        }
                    }
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(hasPhoto ? "Change photo" : "Choose photo", systemImage: "photo")
                    }
                    if photoData != nil {
                        Button("Remove photo", role: .destructive) {
                            photoData = nil
                            photoItem = nil
                        }
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        Section {
            LabeledContent("Code") {
                if code.isEmpty {
                    ProgressView()
                } else {
                    CodeChip(code: code, font: .body)
                }
            }
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
            TextField("Species", text: $species)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSpeciesFocused)
            if isSpeciesFocused && !speciesSuggestions.isEmpty {
                speciesSuggestionRow
            }
        } footer: {
            if isNew {
                Text("The code is generated automatically and printed on the plant's QR label.")
            }
        }
    }

    /// Tappable chips with species already used for other plants.
    private var speciesSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(speciesSuggestions.prefix(10), id: \.self) { suggestion in
                    Button(suggestion) {
                        species = suggestion
                        isSpeciesFocused = false
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .font(.subheadline)
                }
            }
        }
        .accessibilityLabel(Text("Species suggestions"))
    }

    private var acquiredSection: some View {
        Section {
            Toggle("Purchase date known", isOn: $hasAcquiredDate.animation())
            if hasAcquiredDate {
                DatePicker("Bought on", selection: $acquiredDate, in: ...Date.now, displayedComponents: .date)
            }
        }
    }

    private var parentSection: some View {
        Section {
            Picker("Parent plant", selection: $parent) {
                Text("None").tag(Plant?.none)
                ForEach(parentCandidates) { candidate in
                    Text(verbatim: "\(candidate.name) (\(candidate.code))").tag(Optional(candidate))
                }
            }
        } footer: {
            Text("Set this if the plant was grown from a cutting of another plant.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Watering reminder", isOn: $reminderEnabled.animation())
            if reminderEnabled {
                Stepper(value: $wateringIntervalDays, in: 1...60) {
                    Text("Every ^[\(wateringIntervalDays) day](inflect: true)")
                }
            }
        }
    }

    // MARK: - Data

    /// Distinct species of other plants matching the current input.
    private var speciesSuggestions: [String] {
        let input = species.trimmingCharacters(in: .whitespaces)
        let known = Set(allPlants.map(\.species).filter { !$0.isEmpty })
        return known
            .filter { input.isEmpty || ($0.localizedStandardContains(input) && $0 != input) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// All plants except this one and its descendants (prevents cycles).
    private var parentCandidates: [Plant] {
        guard let plant else { return allPlants }
        return allPlants.filter { !$0.isSelfOrDescendant(of: plant) }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let plant {
            code = plant.code
            name = plant.name
            species = plant.species
            hasAcquiredDate = plant.acquiredDate != nil
            acquiredDate = plant.acquiredDate ?? .now
            parent = plant.parent
            reminderEnabled = plant.wateringIntervalDays != nil
            wateringIntervalDays = plant.wateringIntervalDays ?? 7
            notes = plant.notes
            photoData = plant.profilePhoto
        } else {
            do {
                let usedCodes = try modelContext.usedPlantCodes()
                if let presetCode, !usedCodes.contains(presetCode.rawValue) {
                    code = presetCode.rawValue
                } else {
                    code = try PlantCode.generate(excluding: usedCodes).rawValue
                }
            } catch {
                errorMessage = String(localized: "No free plant code could be generated.")
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = await ImageProcessing.preparedJPEG(from: data) else {
                errorMessage = String(localized: "The photo could not be loaded.")
                return
            }
            photoData = jpeg
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let target = plant ?? Plant(code: code, name: trimmedName)
        target.name = trimmedName
        target.species = species.trimmingCharacters(in: .whitespacesAndNewlines)
        target.acquiredDate = hasAcquiredDate ? acquiredDate : nil
        target.parent = parent
        target.wateringIntervalDays = reminderEnabled ? wateringIntervalDays : nil
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.profilePhoto = photoData

        if isNew {
            modelContext.insert(target)
        }
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if isNew {
            onCreate(target)
        }
        dismiss()
    }
}

#Preview("New") {
    PlantFormView(plant: nil)
        .modelContainer(SampleData.makePreviewContainer())
}
