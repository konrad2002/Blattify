import SwiftUI

/// Prominent buttons for the most common care actions on the plant profile.
struct QuickActionsView: View {
    let onWater: (WateringKind) -> Void
    let onNewLeaf: () -> Void
    let onForm: (EventKind) -> Void
    let onPest: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(WateringKind.allCases, id: \.self) { kind in
                    Button {
                        onWater(kind)
                    } label: {
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.symbolName)
                        }
                    }
                }
                Divider()
                Button("With details…", systemImage: "square.and.pencil") { onForm(.watering) }
            } label: {
                QuickActionLabel(title: "Water", systemImage: "drop.fill", tint: EventKind.watering.tint)
            }

            Button {
                onForm(.fertilizing)
            } label: {
                QuickActionLabel(title: "Fertilize", systemImage: EventKind.fertilizing.symbolName,
                                 tint: EventKind.fertilizing.tint)
            }

            Button(action: onNewLeaf) {
                QuickActionLabel(title: "New leaf", systemImage: EventKind.newLeaf.symbolName,
                                 tint: EventKind.newLeaf.tint)
            }

            Menu {
                Button {
                    onForm(.repotting)
                } label: {
                    Label("Repotting", systemImage: EventKind.repotting.symbolName)
                }
                Button {
                    onForm(.cutting)
                } label: {
                    Label("Cutting", systemImage: EventKind.cutting.symbolName)
                }
                Button(action: onPest) {
                    Label("Pest infestation", systemImage: "ladybug")
                }
                Button {
                    onForm(.newLeaf)
                } label: {
                    Label("New leaf with details…", systemImage: EventKind.newLeaf.symbolName)
                }
            } label: {
                QuickActionLabel(title: "More", systemImage: "ellipsis", tint: .secondary)
            }
        }
        .buttonStyle(.glass)
        .menuStyle(.button)
    }
}

private struct QuickActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                // Fixed height so short symbols (ellipsis) keep all buttons equally tall.
                .frame(height: 28)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
