import CoreImage
import Foundation
import Testing
@testable import Blattify

struct P22ProtocolTests {
    private func hex(_ string: String) -> Data {
        Data(string.split(separator: " ").compactMap { UInt8($0, radix: 16) })
    }

    @Test func jobMatchesCapturedFormat() throws {
        let raster = Data(repeating: 0xFF, count: P22Protocol.rasterLength)
        let job = try P22Protocol.printJob(raster: raster)

        // Header and suffix of the successfully printed capture.
        let header = Data("SIZE 15 mm,14 mm\r\nGAP 0,0\r\nDIRECTION 0,0\r\nDENSITY 15\r\nCLS\r\nBITMAP 0,0,12,112,1,".utf8)
        #expect(header.count == 79)
        #expect(job.count == 1434)
        #expect(job.prefix(79) == header)
        #expect(job.dropFirst(79).prefix(1344) == raster)
        #expect(job.suffix(11) == Data("\r\nPRINT 1\r\n".utf8))
    }

    @Test func jobRejectsWrongRasterLength() {
        #expect(throws: P22Protocol.JobError.wrongRasterLength(10)) {
            try P22Protocol.printJob(raster: Data(count: 10))
        }
    }

    @Test(arguments: [509, 512, 182, 20, 1434, 5000])
    func chunksPreserveOrderAndRespectMaximum(maxLength: Int) throws {
        let job = try P22Protocol.printJob(raster: Data((0..<P22Protocol.rasterLength).map { UInt8($0 % 256) }))
        let chunks = P22Protocol.chunks(of: job, maxLength: maxLength)
        #expect(chunks.allSatisfy { $0.count <= maxLength && !$0.isEmpty })
        #expect(chunks.reduce(Data(), +) == job)
        #expect(chunks.count == (job.count + maxLength - 1) / maxLength)
    }

    @Test func chunksOfSlicedData() {
        let data = Data([1, 2, 3, 4, 5, 6, 7]).dropFirst(2)
        #expect(P22Protocol.chunks(of: data, maxLength: 2) == [Data([3, 4]), Data([5, 6]), Data([7])])
    }

    @Test func parsesObservedStatusResponses() {
        #expect(P22Protocol.batteryPayload(from: hex("42 41 54 54 45 52 59 20 99 00 0d 0a")) == hex("99 00"))
        #expect(P22Protocol.configPayload(from: hex("43 4f 4e 46 49 47 20 00 cb 00 00 02 00 00 08 02 01 0d 0a"))
                == hex("00 cb 00 00 02 00 00 08 02 01"))
    }

    @Test func rejectsUnknownOrMalformedResponses() {
        // Responses to the unknown queries (one contains 0a in the middle, one is a single byte).
        #expect(P22Protocol.batteryPayload(from: hex("00 0c 01 22 03 00 03 00 00 12 15 0a 0f 0e 55 4f")) == nil)
        #expect(P22Protocol.batteryPayload(from: hex("00")) == nil)
        // Truncated battery response without CR LF, and a config response to a battery query.
        #expect(P22Protocol.batteryPayload(from: hex("42 41 54 54 45 52 59 20 99")) == nil)
        #expect(P22Protocol.batteryPayload(from: hex("43 4f 4e 46 49 47 20 00 0d 0a")) == nil)
        #expect(P22Protocol.configPayload(from: Data()) == nil)
    }

    @Test func hexString() {
        #expect(hex("99 00 0d").hexString == "99 00 0d")
    }
}

struct P22LabelRendererTests {
    private let url = "blattify://plant/AB-23"

    private func isBlack(_ raster: Data, x: Int, y: Int) -> Bool {
        raster[y * P22Protocol.bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8)) == 0
    }

    @Test func labelHasPrinterGeometryAndGap() throws {
        let label = try P22LabelRenderer.label(qrText: url, heading: "AB-23")
        #expect(label.raster.count == P22Protocol.rasterLength)
        #expect(label.moduleSize >= P22LabelRenderer.minimumModuleSize)

        let rows = 0..<P22Protocol.labelHeight
        let blackRows = rows.filter { y in (0..<96).contains { isBlack(label.raster, x: $0, y: y) } }
        // Heading ink in rows 0..<13, rows 13–15 white, QR starts at row 16.
        #expect(blackRows.contains { $0 < 13 })
        #expect(!blackRows.contains(13) && !blackRows.contains(14) && !blackRows.contains(15))
        #expect(blackRows.contains(16))
        // Finder pattern corner: QR fills the full width.
        #expect(isBlack(label.raster, x: 0, y: 16))
        #expect(isBlack(label.raster, x: 95, y: 16))
        #expect(isBlack(label.raster, x: 0, y: 111))
    }

    @Test func whiteIsEncodedAsOne() throws {
        let label = try P22LabelRenderer.label(qrText: url, heading: "AB-23")
        // Rows 13–15 are completely white → twelve 0xFF bytes each.
        let gap = label.raster[(13 * 12)..<(16 * 12)]
        #expect(gap.allSatisfy { $0 == 0xFF })
    }

    @Test func qrDecodesToPlantURL() throws {
        let label = try P22LabelRenderer.label(qrText: url, heading: "AB-23")
        let image = try #require(P22LabelRenderer.image(fromRaster: label.raster))
        // The physical label provides the quiet zone; simulate it with a white border.
        let qrOnly = CIImage(cgImage: image)
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 96))
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let background = CIImage(color: .white).cropped(to: qrOnly.extent.insetBy(dx: -64, dy: -64))
        let composed = qrOnly.composited(over: background)

        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let messages = detector.features(in: composed).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(messages == [url])
    }

    @Test func rejectsInvalidInput() {
        #expect(throws: P22LabelRenderer.RenderError.emptyQRText) {
            try P22LabelRenderer.label(qrText: "", heading: "AB-23")
        }
        #expect(throws: P22LabelRenderer.RenderError.invalidHeading) {
            try P22LabelRenderer.label(qrText: url, heading: "AB-2")
        }
        #expect(throws: P22LabelRenderer.RenderError.invalidHeading) {
            try P22LabelRenderer.label(qrText: url, heading: "ÄB-23")
        }
        // Too much data for modules of at least two pixels.
        #expect(throws: P22LabelRenderer.RenderError.qrTooLarge) {
            try P22LabelRenderer.label(qrText: String(repeating: "x", count: 300), heading: "AB-23")
        }
    }

    @Test func packingIsMSBFirst() {
        var black = [Bool](repeating: false, count: 16)
        black[0] = true
        black[9] = true
        #expect(P22LabelRenderer.pack(black, width: 16, height: 1) == Data([0x7F, 0xBF]))
    }
}
