import SwiftUI

/// One pest infestation episode in a list.
struct InfestationRow: View {
    let infestation: PestInfestation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "ladybug.fill")
                .font(.title3)
                .foregroundStyle(infestation.isActive ? MatrixCategory.pest.color : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: infestation.displayName)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if infestation.isActive {
                        Text("Active")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(MatrixCategory.pest.color.opacity(0.15), in: .capsule)
                            .foregroundStyle(MatrixCategory.pest.color)
                    }
                }
                periodText
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !infestation.notes.isEmpty {
                    Text(infestation.notes)
                        .font(.subheadline)
                }
                if let photos = infestation.photos, !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(photos.sorted { $0.createdAt < $1.createdAt }) { photo in
                                PlantPhotoView(data: photo.imageData, pointSize: 56, cornerRadius: 8)
                                    .frame(width: 56, height: 56)
                            }
                        }
                    }
                    .accessibilityLabel(Text("^[\(photos.count) photo](inflect: true)"))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var periodText: Text {
        let start = infestation.startDate.formatted(date: .abbreviated, time: .omitted)
        if let resolved = infestation.resolvedDate {
            let end = resolved.formatted(date: .abbreviated, time: .omitted)
            return Text("\(start) – \(end)")
        }
        return Text("Since \(start)")
    }
}
