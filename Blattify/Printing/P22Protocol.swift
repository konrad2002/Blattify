import CoreBluetooth
import Foundation

/// GATT identifiers of the P22 printer (`CBUUID` is not `Sendable`, so these stay on the main actor).
enum P22GATT {
    /// Advertised service (not returned as a GATT service after connecting).
    static let advertisedService = CBUUID(string: "AF30")
    static let advertisedName = "P22"

    static let printService = CBUUID(string: "FF00")
    /// Write without response: status queries and the print stream.
    static let writeCharacteristic = CBUUID(string: "FF02")
    /// Notify: status query responses.
    static let responseCharacteristic = CBUUID(string: "FF01")
    /// Notify characteristics the original app also subscribed to (purpose unknown).
    static let auxiliaryNotifyCharacteristics = [CBUUID(string: "FF03"), CBUUID(string: "AE02")]
    static let auxiliaryService = CBUUID(string: "AE00")
}

/// Reverse-engineered protocol of the P22 BLE label printer (see `p22/printer/P22_PROTOCOL.md`).
/// Only the observed, successfully printed job format is used; unknown values are not interpreted.
nonisolated enum P22Protocol {
    // MARK: Status queries

    static let batteryQuery = Data("BATTERY?\r\n".utf8)
    static let configQuery = Data("CONFIG?\r\n".utf8)
    /// Sent by the original app before every print; meaning unknown.
    static let unknownQueryA = Data([0x1B, 0x21, 0x6F, 0x0D, 0x0A])
    static let unknownQueryB = Data([0x1B, 0x21, 0x3F, 0x0D, 0x0A])

    /// Payload after `BATTERY ` up to the trailing CR LF, or `nil` for any other response.
    /// The payload (observed: `99 00`) is binary and its meaning is not decoded.
    static func batteryPayload(from response: Data) -> Data? {
        payload(of: response, prefix: "BATTERY ")
    }

    /// Payload after `CONFIG ` up to the trailing CR LF (observed: ten binary bytes, not decoded).
    static func configPayload(from response: Data) -> Data? {
        payload(of: response, prefix: "CONFIG ")
    }

    private static func payload(of response: Data, prefix: String) -> Data? {
        let prefixBytes = Data(prefix.utf8)
        let suffix = Data([0x0D, 0x0A])
        guard response.count >= prefixBytes.count + suffix.count,
              response.starts(with: prefixBytes),
              response.suffix(2) == suffix else { return nil }
        return Data(response.dropFirst(prefixBytes.count).dropLast(suffix.count))
    }

    // MARK: Print job

    /// The only physically verified label geometry: 96 × 112 pixels on 15 × 14 mm labels.
    static let labelWidth = 96
    static let labelHeight = 112
    static let bytesPerRow = labelWidth / 8
    static let rasterLength = bytesPerRow * labelHeight
    static let labelSizeMillimeters = (width: 15, height: 14)

    enum JobError: Error, Equatable {
        case wrongRasterLength(Int)
    }

    /// Builds the captured job format with a new raster. The raster bytes follow the last comma of
    /// `BITMAP` directly (no newline); bit `1` = white, `0` = black, rows top to bottom, MSB first.
    static func printJob(raster: Data) throws(JobError) -> Data {
        guard raster.count == rasterLength else { throw .wrongRasterLength(raster.count) }
        var job = Data()
        job.append(contentsOf: Array("SIZE \(labelSizeMillimeters.width) mm,\(labelSizeMillimeters.height) mm\r\n".utf8))
        job.append(contentsOf: Array("GAP 0,0\r\n".utf8))
        job.append(contentsOf: Array("DIRECTION 0,0\r\n".utf8))
        job.append(contentsOf: Array("DENSITY 15\r\n".utf8))
        job.append(contentsOf: Array("CLS\r\n".utf8))
        job.append(contentsOf: Array("BITMAP 0,0,\(bytesPerRow),\(labelHeight),1,".utf8))
        job.append(raster)
        job.append(contentsOf: Array("\r\nPRINT 1\r\n".utf8))
        return job
    }

    /// Splits `data` into ordered chunks of at most `maxLength` bytes (the connection's current
    /// maximum write-without-response length).
    static func chunks(of data: Data, maxLength: Int) -> [Data] {
        guard maxLength > 0 else { return [] }
        return stride(from: 0, to: data.count, by: maxLength).map { start in
            Data(data[data.startIndex + start ..< data.startIndex + min(start + maxLength, data.count)])
        }
    }
}

extension Data {
    /// Space-separated hex bytes, e.g. `99 00`, for diagnostics.
    nonisolated var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
