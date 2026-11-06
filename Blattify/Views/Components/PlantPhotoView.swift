import SwiftUI

/// Shows a plant photo (decoded asynchronously as a thumbnail) or a leaf placeholder.
struct PlantPhotoView: View {
    let data: Data?
    /// Thumbnail size in points; the image is decoded at this size × display scale.
    var pointSize: CGFloat = 60
    var cornerRadius: CGFloat = 12

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.tint.opacity(0.15))
                        Image(systemName: "leaf.fill")
                            .font(.system(size: pointSize * 0.35))
                            .foregroundStyle(.tint)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
            .task(id: dataFingerprint) {
                guard let data else {
                    image = nil
                    return
                }
                image = await ImageProcessing.thumbnail(from: data, maxPixelSize: pointSize * displayScale)
            }
    }

    /// Cheap identity for `task(id:)` so photo data is not compared byte by byte on every update.
    private var dataFingerprint: Int? {
        guard let data else { return nil }
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data.prefix(64))
        hasher.combine(data.suffix(64))
        return hasher.finalize()
    }
}

#Preview {
    PlantPhotoView(data: nil, pointSize: 120)
        .frame(width: 120, height: 120)
}
