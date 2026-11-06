import SwiftUI

/// Small floating confirmation with an undo button.
struct UndoToast: View {
    let title: Text
    let systemImage: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect()
        .padding(.horizontal)
    }
}

#Preview {
    UndoToast(title: Text("Watering logged"), systemImage: "drop.fill") {}
}
