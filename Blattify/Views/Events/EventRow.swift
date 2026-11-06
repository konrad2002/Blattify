import SwiftUI

/// One care event in a history list.
struct EventRow: View {
    let event: PlantEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(event.kind?.tint ?? .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    title
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(event.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let details {
                    Text(verbatim: details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.subheadline)
                }
                if let photos = event.photos, !photos.isEmpty {
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

    private var symbolName: String {
        if let wateringKind = event.wateringKind {
            return wateringKind.symbolName
        }
        return event.kind?.symbolName ?? "questionmark.circle"
    }

    private var title: Text {
        if let kind = event.kind {
            Text(kind.title)
        } else {
            Text("Unknown event")
        }
    }

    /// Kind-specific details, e.g. "Soaked", "Compo · 5 ml/L" or "24 cm · Aroid mix".
    private var details: String? {
        var parts: [String] = []
        switch event.kind {
        case .watering:
            if let wateringKind = event.wateringKind {
                parts.append(String(localized: wateringKind.title))
            }
        case .fertilizing:
            parts.append(contentsOf: [event.fertilizerName, event.fertilizerAmount].compactMap(\.self))
        case .repotting:
            if let diameter = event.potDiameterCm {
                parts.append(PlantEvent.formattedPotDiameter(diameter))
            }
            if let substrate = event.substrate {
                parts.append(substrate)
            }
        case .cutting, .newLeaf, nil:
            break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
