import SwiftUI
import SwiftData
import PhotosUI

/// Request to show the event form for a new (`event == nil`) or existing event.
struct EventFormRequest: Identifiable {
    let id = UUID()
    let kind: EventKind
    var event: PlantEvent?
    /// Preset date for new events (e.g. a day tapped in the activity matrix).
    var date: Date?
}

/// Create or edit a care event. Shows the fields relevant for the event's kind.
struct EventFormView: View {
    let plant: Plant
    let kind: EventKind
    let event: PlantEvent?
    var initialDate: Date?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var wateringKind = WateringKind.soaked
    @State private var fertilizerName = ""
    @State private var fertilizerAmount = ""
    @State private var potDiameterText = ""
    @State private var substrate = ""
    @State private var note = ""
    @State private var photos: [DraftPhoto] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false
    @State private var isProcessingPhotos = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    @State private var fertilizerNameSuggestions: [String] = []
    @State private var fertilizerAmountSuggestions: [String] = []
    @State private var substrateSuggestions: [String] = []
    @FocusState private var focusedField: Field?

    private enum Field {
        case fertilizerName, fertilizerAmount, substrate
    }

    init(plant: Plant, kind: EventKind, event: PlantEvent? = nil, initialDate: Date? = nil) {
        self.plant = plant
        self.kind = kind
        self.event = event
        self.initialDate = initialDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now)
                }
                kindSection
                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                photoSection
            }
            .navigationTitle(Text(kind.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isProcessingPhotos || (kind == .repotting && !isPotDiameterValid))
                }
            }
            .onAppear(perform: loadIfNeeded)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPhotos(from: items) }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPicker { image in
                    Task { await addPhoto(from: image) }
                }
                .ignoresSafeArea()
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

    @ViewBuilder
    private var kindSection: some View {
        switch kind {
        case .watering:
            Section("Kind of watering") {
                Picker("Kind of watering", selection: $wateringKind) {
                    ForEach(WateringKind.allCases, id: \.self) { kind in
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.symbolName)
                        }
                        .tag(kind)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        case .fertilizing:
            Section("Fertilizer") {
                TextField("Fertilizer", text: $fertilizerName)
                    .focused($focusedField, equals: .fertilizerName)
                suggestionRow(for: .fertilizerName, input: fertilizerName, values: fertilizerNameSuggestions) {
                    fertilizerName = $0
                }
                TextField("Amount (e.g. 2 ml/L)", text: $fertilizerAmount)
                    .focused($focusedField, equals: .fertilizerAmount)
                suggestionRow(for: .fertilizerAmount, input: fertilizerAmount, values: fertilizerAmountSuggestions) {
                    fertilizerAmount = $0
                }
            }
        case .repotting:
            Section("New pot") {
                LabeledContent("Pot diameter") {
                    HStack(spacing: 4) {
                        TextField(text: $potDiameterText, prompt: Text(verbatim: "18")) {
                            Text("Pot diameter")
                        }
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        Text(verbatim: "cm")
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("Substrate", text: $substrate)
                    .focused($focusedField, equals: .substrate)
                suggestionRow(for: .substrate, input: substrate, values: substrateSuggestions) {
                    substrate = $0
                }
            }
        case .cutting, .newLeaf:
            EmptyView()
        }
    }

    @ViewBuilder
    private func suggestionRow(
        for field: Field,
        input: String,
        values: [String],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let matches = SuggestionChips.matches(for: input, in: values)
        if focusedField == field && !matches.isEmpty {
            SuggestionChips(suggestions: matches) { value in
                onSelect(value)
                focusedField = nil
            }
        }
    }

    private var photoSection: some View {
        Section("Photos") {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            PlantPhotoView(data: photo.data, pointSize: 80)
                                .frame(width: 80, height: 80)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.removeAll { $0.id == photo.id }
                                    } label: {
                                        Label("Remove photo", systemImage: "xmark.circle.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("Add photos", systemImage: "photo.on.rectangle")
            }
            if CameraPicker.isAvailable {
                Button {
                    isTakingPhoto = true
                } label: {
                    Label("Take photo", systemImage: "camera")
                }
            }
            if isProcessingPhotos {
                ProgressView()
            }
        }
    }

    // MARK: - Data

    private var parsedPotDiameter: Double? {
        let text = potDiameterText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (try? Double(text, format: .number)) ?? Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Empty is allowed; otherwise a positive number.
    private var isPotDiameterValid: Bool {
        potDiameterText.trimmingCharacters(in: .whitespaces).isEmpty || (parsedPotDiameter ?? 0) > 0
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        if let event {
            date = event.date
            wateringKind = event.wateringKind ?? .soaked
            fertilizerName = event.fertilizerName ?? ""
            fertilizerAmount = event.fertilizerAmount ?? ""
            potDiameterText = event.potDiameterCm?.formatted(.number) ?? ""
            substrate = event.substrate ?? ""
            note = event.note
            photos = (event.photos ?? [])
                .sorted { $0.createdAt < $1.createdAt }
                .map { DraftPhoto(id: $0.id, data: $0.imageData, existing: $0) }
        } else {
            date = initialDate ?? .now
            if kind == .fertilizing, let last = plant.lastFertilizing {
                // Most plants get the same fertilizer each time.
                fertilizerName = last.fertilizerName ?? ""
                fertilizerAmount = last.fertilizerAmount ?? ""
            }
        }

        do {
            switch kind {
            case .fertilizing:
                fertilizerNameSuggestions = try modelContext.recentEventValues(of: .fertilizing) { $0.fertilizerName }
                fertilizerAmountSuggestions = try modelContext.recentEventValues(of: .fertilizing) { $0.fertilizerAmount }
            case .repotting:
                substrateSuggestions = try modelContext.recentEventValues(of: .repotting) { $0.substrate }
            case .watering, .cutting, .newLeaf:
                break
            }
        } catch {
            // Suggestions are optional; the form works without them.
            fertilizerNameSuggestions = []
        }
    }

    private func addPhotos(from items: [PhotosPickerItem]) async {
        isProcessingPhotos = true
        defer {
            isProcessingPhotos = false
            pickerItems = []
        }
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let jpeg = await ImageProcessing.preparedJPEG(from: data) {
                    photos.append(DraftPhoto(id: UUID(), data: jpeg, existing: nil))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addPhoto(from image: UIImage) async {
        isProcessingPhotos = true
        defer { isProcessingPhotos = false }
        if let jpeg = await ImageProcessing.preparedJPEG(from: image) {
            photos.append(DraftPhoto(id: UUID(), data: jpeg, existing: nil))
        }
    }

    private func save() {
        let target: PlantEvent
        if let event {
            target = event
        } else {
            target = PlantEvent(kind: kind)
            modelContext.insert(target)
            target.plant = plant
        }

        target.date = date
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.wateringKind = kind == .watering ? wateringKind : nil
        target.fertilizerName = kind == .fertilizing ? fertilizerName.nonEmptyTrimmed : nil
        target.fertilizerAmount = kind == .fertilizing ? fertilizerAmount.nonEmptyTrimmed : nil
        target.potDiameterCm = kind == .repotting ? parsedPotDiameter : nil
        target.substrate = kind == .repotting ? substrate.nonEmptyTrimmed : nil

        // Photos: delete removed ones, add new ones.
        let keptIDs = Set(photos.compactMap { $0.existing?.id })
        for photo in target.photos ?? [] where !keptIDs.contains(photo.id) {
            modelContext.delete(photo)
        }
        for draft in photos where draft.existing == nil {
            let photo = EventPhoto(imageData: draft.data)
            modelContext.insert(photo)
            photo.event = target
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A photo in the form: either already stored or newly added.
private struct DraftPhoto: Identifiable {
    let id: UUID
    let data: Data?
    let existing: EventPhoto?
}

extension String {
    /// Trimmed string, or `nil` if it is empty after trimming.
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Fertilizing") {
    let container = SampleData.makePreviewContainer()
    let plant = (try? container.mainContext.fetch(FetchDescriptor<Plant>()).first) ?? Plant(code: "AB-23", name: "Preview")
    EventFormView(plant: plant, kind: .fertilizing)
        .modelContainer(container)
}

#Preview("Repotting") {
    let container = SampleData.makePreviewContainer()
    let plant = (try? container.mainContext.fetch(FetchDescriptor<Plant>()).first) ?? Plant(code: "AB-23", name: "Preview")
    EventFormView(plant: plant, kind: .repotting)
        .modelContainer(container)
}
