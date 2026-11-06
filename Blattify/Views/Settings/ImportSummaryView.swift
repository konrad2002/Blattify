import SwiftUI

/// Shown after an import: what was added or updated, and which plants got a new code.
struct ImportSummaryView: View {
    let summary: ImportSummary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if summary.isEmpty {
                    Section {
                        Label("Everything in the backup was already in Blattify.", systemImage: "checkmark.circle")
                    }
                } else {
                    Section {
                        row("Plants added", summary.plantsAdded, systemImage: "leaf")
                        row("Plants updated", summary.plantsUpdated, systemImage: "arrow.triangle.2.circlepath")
                        row("Entries added", summary.eventsAdded, systemImage: "calendar.badge.plus")
                        row("Pest records added", summary.infestationsAdded, systemImage: "ladybug")
                        row("Photos added", summary.photosAdded, systemImage: "photo")
                    }
                }
                if !summary.codeChanges.isEmpty {
                    Section {
                        ForEach(summary.codeChanges, id: \.newCode) { change in
                            LabeledContent {
                                HStack(spacing: 6) {
                                    Text(verbatim: change.oldCode)
                                        .strikethrough()
                                    Image(systemName: "arrow.right")
                                    CodeChip(code: change.newCode)
                                }
                            } label: {
                                Text(change.plantName)
                            }
                        }
                    } header: {
                        Text("New codes")
                    } footer: {
                        Text("These codes were already used by other plants. Print new QR labels for them.")
                    }
                }
            }
            .navigationTitle("Import finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: LocalizedStringKey, _ value: Int, systemImage: String) -> some View {
        LabeledContent {
            Text(value, format: .number)
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

extension ImportSummary: Identifiable {
    /// Only one summary is shown at a time.
    var id: Int { 0 }
}

#Preview {
    ImportSummaryView(summary: ImportSummary(
        plantsAdded: 3, plantsUpdated: 1, eventsAdded: 120, infestationsAdded: 2, photosAdded: 14,
        codeChanges: [.init(plantName: "Monty", oldCode: "MN-24", newCode: "QX-7K")]
    ))
}
