import Foundation
import ImageIO
import UIKit

/// Image downscaling and encoding, performed off the main actor.
nonisolated enum ImageProcessing {
    /// Longest side of stored photos, keeps iCloud storage small.
    static let storedMaxPixelSize: CGFloat = 2048
    static let jpegQuality: CGFloat = 0.8

    /// Downscales arbitrary image data (HEIC, PNG, JPEG, …) and re-encodes it as JPEG for storage.
    @concurrent
    static func preparedJPEG(from data: Data) async -> Data? {
        guard let image = downscaledImage(from: data, maxPixelSize: storedMaxPixelSize) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: jpegQuality)
    }

    /// Same as `preparedJPEG(from:)` for camera images; encoding happens off the main actor too.
    @concurrent
    static func preparedJPEG(from image: UIImage) async -> Data? {
        guard let data = image.jpegData(compressionQuality: 1) else { return nil }
        return await preparedJPEG(from: data)
    }

    /// A small image for lists and headers. `maxPixelSize` is in pixels, not points.
    @concurrent
    static func thumbnail(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        downscaledImage(from: data, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
    }

    /// Uses ImageIO so the full-size image is never decoded into memory; applies the EXIF orientation.
    private static func downscaledImage(from data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
