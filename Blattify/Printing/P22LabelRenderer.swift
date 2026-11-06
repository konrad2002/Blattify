import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation

/// Renders the printer label: plant code centered in the top 16 rows (bottom of the text at row 13,
/// three white rows as gap) and the QR code filling 96 × 96 pixels below, without antialiasing.
/// Mirrors `p22/printer/print_qr.py`.
nonisolated enum P22LabelRenderer {
    struct Label: Sendable {
        /// 1-bit raster in printer format (1 = white), `P22Protocol.rasterLength` bytes.
        let raster: Data
        /// Smallest QR module size in pixels.
        let moduleSize: Int
    }

    enum RenderError: Error, Equatable {
        case emptyQRText
        case invalidHeading
        case qrTooLarge
        case headingDoesNotFit
        case renderingFailed
    }

    static let headingHeight = 16
    static let headingGap = 3
    static let qrSide = 96
    static let minimumModuleSize = 2

    static func label(qrText: String, heading: String) throws(RenderError) -> Label {
        guard !qrText.isEmpty else { throw .emptyQRText }
        // Exactly five printable ASCII characters, like the reference implementation.
        guard heading.count == 5, heading.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else {
            throw .invalidHeading
        }
        guard let matrix = qrMatrix(for: qrText) else { throw .renderingFailed }
        let size = matrix.count
        let moduleSize = qrSide / size
        guard moduleSize >= minimumModuleSize else { throw .qrTooLarge }

        let width = P22Protocol.labelWidth
        let height = P22Protocol.labelHeight
        var black = [Bool](repeating: false, count: width * height)

        // Heading: rendered with Core Text, then thresholded.
        let headingPixels = try headingBitmap(heading)
        for index in headingPixels.indices where headingPixels[index] {
            black[index] = true
        }

        // QR: distribute pixel rounding across modules instead of adding margins.
        for row in 0..<size {
            for column in 0..<size where matrix[row][column] {
                let x0 = column * qrSide / size, x1 = (column + 1) * qrSide / size
                let y0 = headingHeight + row * qrSide / size, y1 = headingHeight + (row + 1) * qrSide / size
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        black[y * width + x] = true
                    }
                }
            }
        }

        return Label(raster: pack(black, width: width, height: height), moduleSize: moduleSize)
    }

    /// Packs pixels MSB first; bit 1 = white, 0 = black.
    static func pack(_ black: [Bool], width: Int, height: Int) -> Data {
        let bytesPerRow = width / 8
        var bytes = [UInt8](repeating: 0xFF, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width where black[y * width + x] {
                bytes[y * bytesPerRow + x / 8] &= ~(0x80 >> UInt8(x % 8))
            }
        }
        return Data(bytes)
    }

    /// Converts a raster back to a grayscale image (for previews and tests).
    static func image(fromRaster raster: Data, width: Int = P22Protocol.labelWidth, height: Int = P22Protocol.labelHeight) -> CGImage? {
        let bytesPerRow = width / 8
        guard raster.count == bytesPerRow * height else { return nil }
        var gray = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let byte = raster[raster.startIndex + y * bytesPerRow + x / 8]
                if byte & (0x80 >> UInt8(x % 8)) == 0 {
                    gray[y * width + x] = 0
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - QR matrix

    /// QR modules (error correction M, like the reference) without quiet zone; `true` = black.
    static func qrMatrix(for text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }

        let width = cgImage.width, height = cgImage.height
        var gray = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(data: &gray, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Core Image adds a quiet zone; the finder patterns make the black bounding box the matrix.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where gray[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxX - minX == maxY - minY else { return nil }
        return (minY...maxY).map { y in
            (minX...maxX).map { x in gray[y * width + x] < 128 }
        }
    }

    // MARK: - Heading

    /// Black pixels of the heading for the whole label (only the top `headingHeight` rows are used).
    private static func headingBitmap(_ text: String) throws(RenderError) -> [Bool] {
        let width = P22Protocol.labelWidth
        let height = headingHeight
        let maxTextHeight = CGFloat(headingHeight - headingGap)
        var gray = [UInt8](repeating: 255, count: width * height)

        let drawn: Bool = gray.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setShouldAntialias(false)
            context.setAllowsFontSmoothing(false)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Largest bold monospaced font whose ink fits 96 × 13 pixels.
            for size in stride(from: 16.0, through: 8.0, by: -1.0) {
                let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                let bounds = CTLineGetImageBounds(line, context)
                guard bounds.width <= CGFloat(width), bounds.height <= maxTextHeight else { continue }
                // Core Graphics origin is bottom-left: the ink bottom sits `headingGap` rows above the QR.
                let x = ((CGFloat(width) - bounds.width) / 2).rounded(.down) - bounds.minX
                let y = CGFloat(headingGap) - bounds.minY
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
                return true
            }
            return false
        }
        guard drawn else { throw .headingDoesNotFit }

        // Bitmap memory row 0 is the top row of the image.
        var black = [Bool](repeating: false, count: width * P22Protocol.labelHeight)
        for y in 0..<height {
            for x in 0..<width where gray[y * width + x] < 128 {
                black[y * width + x] = true
            }
        }
        return black
    }
}
