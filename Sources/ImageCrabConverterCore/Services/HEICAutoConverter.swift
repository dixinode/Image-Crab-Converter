import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum HEICAutoConverterError: Error, Equatable, Sendable, LocalizedError {
    case cannotOpen(URL)
    case incomplete(URL)
    case scaleFailed(URL)
    case destinationCreateFailed(URL)
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case let .cannotOpen(url): "Cannot open \(url.lastPathComponent)"
        case let .incomplete(url): "\(url.lastPathComponent) is not fully written yet"
        case let .scaleFailed(url): "Cannot scale \(url.lastPathComponent)"
        case let .destinationCreateFailed(url): "Cannot create \(url.lastPathComponent)"
        case let .writeFailed(url): "Cannot write \(url.lastPathComponent)"
        }
    }
}

/// Converts a single HEIC/HEIF photo into a downscaled JPEG next to it.
///
/// Downscaling goes through ImageIO's thumbnail pipeline, which applies the EXIF
/// orientation and keeps the source color profile (iPhone photos are Display P3),
/// so the JPEG looks the same as the original, just smaller.
public struct HEICAutoConverter: Sendable {
    public static let defaultScale = 0.45
    public static let defaultQuality = 1.0
    public static let fileSuffix = "auto_converted"

    public var scale: Double
    public var quality: Double

    public init(scale: Double = Self.defaultScale, quality: Double = Self.defaultQuality) {
        self.scale = min(max(scale, 0.01), 1.0)
        self.quality = min(max(quality, 0.0), 1.0)
    }

    /// True for `.heic` / `.heif` files (any letter case), which is what an iPhone produces.
    public static func isHEIC(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    /// Converts `sourceURL` and returns the URL of the written JPEG.
    @discardableResult
    public func convert(
        sourceURL: URL,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw HEICAutoConverterError.cannotOpen(sourceURL)
        }
        guard CGImageSourceGetStatus(source) == .statusComplete else {
            throw HEICAutoConverterError.incomplete(sourceURL)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else {
            throw HEICAutoConverterError.cannotOpen(sourceURL)
        }

        let targetLongSide = max(1, Int((Double(max(width, height)) * scale).rounded()))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetLongSide,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw HEICAutoConverterError.scaleFailed(sourceURL)
        }

        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let outputURL = Self.uniqueURL(
            directory.appendingPathComponent(Self.outputFileName(for: Self.captureDate(properties: properties, url: sourceURL))),
            fileManager: fileManager
        )

        // Write to a hidden temp file first, then move into place, so nobody
        // (including our own folder watcher) ever sees a half-written JPEG.
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).jpg.tmp")
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw HEICAutoConverterError.destinationCreateFailed(outputURL)
        }

        CGImageDestinationAddImage(destination, image, Self.outputProperties(from: properties, quality: quality) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: tempURL)
            throw HEICAutoConverterError.writeFailed(outputURL)
        }

        do {
            try fileManager.moveItem(at: tempURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw HEICAutoConverterError.writeFailed(outputURL)
        }
        return outputURL
    }

    /// `2026-11-09_10-15-42-auto_converted.jpg`
    public static func outputFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(formatter.string(from: date))-\(fileSuffix).jpg"
    }

    /// When the photo was taken (EXIF), falling back to file creation date, then now.
    static func captureDate(properties: [CFString: Any], url: URL) -> Date {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)

        if let raw {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if let date = formatter.date(from: raw) {
                return date
            }
        }

        if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
            return created
        }
        return Date()
    }

    /// Keeps EXIF/GPS/TIFF/IPTC metadata, resets orientation (pixels are already upright)
    /// and drops the stale pixel-size fields.
    static func outputProperties(from source: [CFString: Any], quality: Double) -> [CFString: Any] {
        var result: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]

        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary] {
            guard var dictionary = source[key] as? [CFString: Any] else { continue }
            if key == kCGImagePropertyExifDictionary {
                dictionary[kCGImagePropertyExifPixelXDimension] = nil
                dictionary[kCGImagePropertyExifPixelYDimension] = nil
            }
            if key == kCGImagePropertyTIFFDictionary {
                dictionary[kCGImagePropertyTIFFOrientation] = 1
            }
            result[key] = dictionary
        }

        result[kCGImagePropertyOrientation] = 1
        return result
    }

    static func uniqueURL(_ url: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()
        var counter = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
