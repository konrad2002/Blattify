import SwiftUI

/// The plant code in a monospaced capsule.
struct CodeChip: View {
    let code: String
    var font: Font = .caption

    var body: some View {
        Text(verbatim: code)
            .font(font.monospaced().weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.15), in: .capsule)
            .foregroundStyle(.tint)
            .accessibilityLabel(Text("Code \(code)"))
    }
}

/// Indicates that the plant needs watering.
struct WateringDueBadge: View {
    var body: some View {
        Image(systemName: "drop.fill")
            .foregroundStyle(.blue)
            .accessibilityLabel(Text("Watering due"))
    }
}

/// Indicates an active pest infestation.
struct PestBadge: View {
    var body: some View {
        Image(systemName: "ladybug.fill")
            .foregroundStyle(.red)
            .accessibilityLabel(Text("Active pest infestation"))
    }
}

/// Capsule label for archived plants ("Given away" / "Died").
struct StatusBadge: View {
    let status: PlantStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.15), in: .capsule)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(spacing: 12) {
        CodeChip(code: "AB-23")
        WateringDueBadge()
        PestBadge()
        StatusBadge(status: .givenAway)
    }
}
