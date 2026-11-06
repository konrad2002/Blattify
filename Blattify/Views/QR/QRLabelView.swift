import SwiftUI
import UniformTypeIdentifiers

/// Printable pot label: QR code, large code and plant name on white.
/// Always rendered in light appearance so printed labels look the same in Dark Mode.
struct QRLabelView: View {
    let code: PlantCode
    let name: String

    /// Label width in points; rendered at scale 3 this gives a ~1020 px wide PNG.
    static let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 12) {
            if let qrImage = QRCodeGenerator.image(for: code.url.absoluteString) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .accessibilityLabel(Text("QR code for \(code.rawValue)"))
            }

            Text(verbatim: code.rawValue)
                .font(.system(size: 52, weight: .bold, design: .monospaced))

            if !name.isEmpty {
                Text(verbatim: name)
                    .font(.system(size: 22, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }

            Label {
                Text(verbatim: "Blattify")
            } icon: {
                Image(systemName: "leaf.fill")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black.opacity(0.45))
        }
        .foregroundStyle(.black)
        .padding(28)
        .frame(width: Self.width)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    /// PNG data of the label (main actor, uses `ImageRenderer`).
    static func renderPNG(code: PlantCode, name: String) -> Data? {
        let renderer = ImageRenderer(content: QRLabelView(code: code, name: name))
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

/// PNG label for `ShareLink` with a meaningful file name.
nonisolated struct QRLabelImage: Transferable {
    let pngData: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { label in
            label.pngData
        }
        .suggestedFileName { $0.fileName }
    }
}

#Preview {
    if let code = PlantCode("MN-24") {
        QRLabelView(code: code, name: "Monty")
            .border(.gray)
    }
}
