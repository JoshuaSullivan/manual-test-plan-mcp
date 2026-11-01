//
//  AttachmentPreparer.swift
//  ManualTestPlan
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Gets an attachment ready to store: images are converted to a format agents can view and capped in size,
/// and everything else is stored exactly as given.
nonisolated enum AttachmentPreparer {
    /// The longest image side kept. Larger images are scaled down; agents downscale anyway, and a Retina
    /// screenshot can otherwise take many megabytes.
    static let maxImagePixelSize = 3000

    /// Name used for image data that arrives without one, such as a pasted screenshot.
    static let anonymousImageName = "Pasted Image"

    /// Formats agents can read directly, so files already in them are kept byte-for-byte.
    private static let passthroughTypes: Set<UTType> = [.png, .jpeg, .gif, .webP]

    /// Prepares one attachment.
    ///
    /// - Images in PNG, JPEG, GIF, or WebP within the size cap are kept as is.
    /// - Other images (TIFF from the pasteboard, HEIC, BMP, …) and oversized images become PNG, scaled so
    ///   the longest side is at most ``maxImagePixelSize``.
    /// - Non-images, including PDFs, are untouched. A missing name becomes "Attachment".
    /// - Parameter payload: What the user dropped, pasted, or picked.
    @concurrent
    static func prepare(_ payload: AttachmentPayload) async -> AttachmentPayload {
        guard let source = imageSource(for: payload.data), let type = imageType(of: source) else {
            var result = payload
            if result.name.isEmpty { result.name = "Attachment" }
            return result
        }

        let longestSide = pixelLongestSide(of: source)
        if passthroughTypes.contains(type), longestSide <= maxImagePixelSize {
            var result = payload
            if result.name.isEmpty { result.name = "\(anonymousImageName).\(type.preferredFilenameExtension ?? "png")" }
            return result
        }

        guard let image = thumbnail(of: source, maxPixelSize: min(longestSide, maxImagePixelSize)),
              let png = encodePNG(image) else {
            var result = payload
            if result.name.isEmpty { result.name = "Attachment" }
            return result
        }
        return AttachmentPayload(name: pngName(for: payload.name), data: png)
    }

    /// A small decoded image for showing in the UI.
    /// - Parameters:
    ///   - data: The image file's bytes.
    ///   - maxPixelSize: The longest side of the result.
    /// - Returns: The thumbnail, or nil if the data isn't a decodable image.
    @concurrent
    static func thumbnail(from data: Data, maxPixelSize: Int) async -> CGImage? {
        guard let source = imageSource(for: data), imageType(of: source) != nil else { return nil }
        return thumbnail(of: source, maxPixelSize: maxPixelSize)
    }

    // MARK: - ImageIO helpers

    private static func imageSource(for data: Data) -> CGImageSource? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return source
    }

    /// The source's type if it is a raster image. PDFs and other documents, which ImageIO can also open,
    /// are rejected so they stay as the user's original file.
    private static func imageType(of source: CGImageSource) -> UTType? {
        guard let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image) else { return nil }
        return type
    }

    private static func pixelLongestSide(of source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height)
    }

    private static func thumbnail(of source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func pngName(for original: String) -> String {
        guard !original.isEmpty else { return "\(anonymousImageName).png" }
        let base = URL(filePath: original).deletingPathExtension().lastPathComponent
        return (base.isEmpty ? anonymousImageName : base) + ".png"
    }
}
