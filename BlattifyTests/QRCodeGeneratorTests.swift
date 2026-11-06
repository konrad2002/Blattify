import CoreImage
import Testing
import UIKit
@testable import Blattify

struct QRCodeGeneratorTests {
    @Test func generatedQRCodeDecodesToPlantURL() throws {
        let code = try #require(PlantCode("AB-23"))
        let image = try #require(QRCodeGenerator.image(for: code.url.absoluteString, pixelSize: 600))
        let cgImage = try #require(image.cgImage)

        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: cgImage)).compactMap { $0 as? CIQRCodeFeature }
        let payload = try #require(features.first?.messageString)

        #expect(payload == "blattify://plant/AB-23")
        #expect(PlantCode(payload: payload) == code)
    }

    @Test func imageIsScaledToRequestedSize() throws {
        let image = try #require(QRCodeGenerator.image(for: "blattify://plant/AB-23", pixelSize: 1024))
        let width = try #require(image.cgImage?.width)
        // Integer scaling: at most one module-scale step below the requested size.
        #expect(width <= 1024)
        #expect(width > 900)
    }
}
