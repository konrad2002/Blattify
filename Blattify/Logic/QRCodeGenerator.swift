import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Creates crisp QR code images with Core Image.
nonisolated enum QRCodeGenerator {
    /// A QR code for `string`, scaled with nearest-neighbour sampling to roughly `pixelSize` pixels.
    /// Error correction level `Q` (~25 %) keeps printed labels readable when slightly damaged.
    static func image(for string: String, pixelSize: CGFloat = 1024) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage else { return nil }

        // Integer scaling keeps every module a sharp square.
        let scale = max(1, (pixelSize / output.extent.width).rounded(.down))
        let scaled = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
