import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImageFactory {
    static func makePNG(width: Int, height: Int, at url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestFailure("Could not create drawing context")
        }

        context.setFillColor(CGColor(red: 0.6, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw TestFailure("Could not create CGImage")
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TestFailure("Could not create image destination")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestFailure("Could not finalize image destination")
        }
    }

    /// HEIC like an iPhone writes it: landscape pixels + EXIF orientation 6 (portrait shot).
    static func makeHEIC(width: Int, height: Int, orientation: Int = 6, dateTimeOriginal: String? = nil, at url: URL) throws {
        let png = url.deletingPathExtension().appendingPathExtension("tmp.png")
        try makePNG(width: width, height: height, at: png)
        defer { try? FileManager.default.removeItem(at: png) }

        guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw TestFailure("Could not create HEIC destination")
        }

        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if let dateTimeOriginal {
            properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: dateTimeOriginal]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestFailure("Could not finalize HEIC")
        }
    }
}
