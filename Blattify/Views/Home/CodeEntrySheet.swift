import SwiftUI
import SwiftData

/// Sheet for typing a plant code. Opens the plant as soon as a complete, known code is entered.
struct CodeEntrySheet: View {
    let onFound: (Plant) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var showsInvalidCharacterHint = false
    @State private var notFoundCode: String?
    /// More than one plant with the same code (only possible after a sync collision).
    @State private var ambiguousMatches: [Plant] = []
    @State private var lookupError: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter the code from the plant's label.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField(text: $text, prompt: Text(verbatim: "XX-XX")) {
                    Text("Plant code")
                }
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isFieldFocused)
                .submitLabel(.go)
                .onSubmit(lookUp)
                .padding(.vertical, 12)
                .background(.fill.tertiary, in: .rect(cornerRadius: 16))
                .onChange(of: text) { _, newValue in
                    handleInput(newValue)
                }

                feedback

                if !ambiguousMatches.isEmpty {
                    ambiguousList
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Open plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open", action: lookUp)
                        .disabled(PlantCode(text) == nil || notFoundCode != nil)
                }
            }
            .onAppear { isFieldFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var feedback: some View {
        if let notFoundCode {
            Label("No plant with code \(notFoundCode)", systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        } else if let lookupError {
            Label(lookupError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        } else if showsInvalidCharacterHint {
            Label("Codes don't use I, L, O, 0 or 1.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var ambiguousList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Several plants share this code. Choose one:")
                .font(.subheadline)
            ForEach(ambiguousMatches) { plant in
                Button {
                    open(plant)
                } label: {
                    PlantRow(plant: plant)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleInput(_ newValue: String) {
        let formatted = PlantCode.formatPartialInput(newValue)
        if formatted.hadInvalidCharacters {
            showsInvalidCharacterHint = true
        }
        notFoundCode = nil
        lookupError = nil
        ambiguousMatches = []
        if formatted.text != newValue {
            text = formatted.text
            // The change above triggers onChange again, which performs the lookup.
            return
        }
        if PlantCode(formatted.text) != nil {
            lookUp()
        }
    }

    private func lookUp() {
        guard let code = PlantCode(text) else { return }
        do {
            let matches = try modelContext.plants(withCode: code.rawValue)
            switch matches.count {
            case 0:
                notFoundCode = code.rawValue
            case 1:
                open(matches[0])
            default:
                ambiguousMatches = matches
            }
        } catch {
            lookupError = error.localizedDescription
        }
    }

    private func open(_ plant: Plant) {
        onFound(plant)
        dismiss()
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CodeEntrySheet { _ in }
        }
        .modelContainer(SampleData.makePreviewContainer())
}
