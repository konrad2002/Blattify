import SwiftUI
import SwiftData
import PhotosUI

/// A photo in a form: either already stored (`existing`) or newly added.
struct DraftPhoto: Identifiable {
    let id: UUID
    let data: Data?
    let existing: EventPhoto?

    static func drafts(from photos: [EventPhoto]?) -> [DraftPhoto] {
        (photos ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map { DraftPhoto(id: $0.id, data: $0.imageData, existing: $0) }
    }
}

/// Form section to add (library or camera) and remove photos of an event or infestation.
struct PhotoDraftSection: View {
    @Binding var photos: [DraftPhoto]
    @Binding var isProcessing: Bool
    @Binding var errorMessage: String?

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isTakingPhoto = false

    var body: some View {
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
            if isProcessing {
                ProgressView()
            }
        }
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
    }

    private func addPhotos(from items: [PhotosPickerItem]) async {
        isProcessing = true
        defer {
            isProcessing = false
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
        isProcessing = true
        defer { isProcessing = false }
        if let jpeg = await ImageProcessing.preparedJPEG(from: image) {
            photos.append(DraftPhoto(id: UUID(), data: jpeg, existing: nil))
        }
    }
}

extension ModelContext {
    /// Deletes stored photos that were removed from `drafts` and inserts the new ones,
    /// connecting each new photo to its owner via `attach`.
    func apply(_ drafts: [DraftPhoto], replacing existing: [EventPhoto]?, attach: (EventPhoto) -> Void) {
        let keptIDs = Set(drafts.compactMap { $0.existing?.id })
        for photo in existing ?? [] where !keptIDs.contains(photo.id) {
            delete(photo)
        }
        for draft in drafts where draft.existing == nil {
            let photo = EventPhoto(imageData: draft.data)
            insert(photo)
            attach(photo)
        }
    }
}
