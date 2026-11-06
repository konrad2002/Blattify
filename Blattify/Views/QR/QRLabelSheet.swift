import SwiftUI

/// Shows a plant's QR label with share and save actions.
struct QRLabelSheet: View {
    let plant: Plant

    @Environment(\.dismiss) private var dismiss
    @State private var pngData: Data?
    @State private var isSaving = false
    @State private var didSave = false
    @State private var errorMessage: String?

    private var code: PlantCode? { PlantCode(plant.code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let code {
                        QRLabelView(code: code, name: plant.name)
                            .clipShape(.rect(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    }

                    Text("Print this label and attach it to the pot. Scanning it with the Camera app opens this plant in Blattify.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    actions
                }
                .padding()
            }
            .navigationTitle("QR label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: plant.name) {
                guard let code else { return }
                pngData = QRLabelView.renderPNG(code: code, name: plant.name)
            }
            .sensoryFeedback(.success, trigger: didSave)
            .alert(
                "Could not save label",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let pngData {
            HStack(spacing: 12) {
                ShareLink(
                    item: QRLabelImage(pngData: pngData, fileName: "Blattify-\(plant.code).png"),
                    preview: SharePreview(Text("QR label \(plant.code)"), image: Image(systemName: "qrcode"))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button {
                    Task { await save(pngData) }
                } label: {
                    Label(didSave ? "Saved" : "Save to Photos",
                          systemImage: didSave ? "checkmark" : "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(isSaving || didSave)
            }
            .controlSize(.large)
        } else {
            ProgressView()
        }
    }

    private func save(_ data: Data) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibrarySaver.savePNG(data)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    QRLabelSheet(plant: Plant(code: "MN-24", name: "Monty", species: "Monstera deliciosa"))
}
