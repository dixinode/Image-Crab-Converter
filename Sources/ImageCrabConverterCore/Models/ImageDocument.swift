import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ExifMetadata: Hashable, Sendable {
    public var cameraModel: String?
    public var focalLength: Double?
    public var aperture: Double?
    public var iso: Int?
    public var shutterSpeed: Double?

    public init(
        cameraModel: String? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil,
        iso: Int? = nil,
        shutterSpeed: Double? = nil
    ) {
        self.cameraModel = cameraModel
        self.focalLength = focalLength
        self.aperture = aperture
        self.iso = iso
        self.shutterSpeed = shutterSpeed
    }
}

public enum ImageFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case heic
    case tiff
    case gif
    case webp
    case bmp
    case pdf
    case raw
    case unknown

    public var preferredExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        case .gif: "gif"
        case .webp: "webp"
        case .bmp: "bmp"
        case .pdf: "pdf"
        case .raw: "raw"
        case .unknown: "img"
        }
    }

    public static func from(typeIdentifier: String?) -> ImageFormat {
        guard let typeIdentifier else { return .unknown }
        let normalized = typeIdentifier.lowercased()
        if normalized.contains("jpeg") || normalized.contains("jpg") { return .jpeg }
        if normalized.contains("png") { return .png }
        if normalized.contains("heic") || normalized.contains("heif") { return .heic }
        if normalized.contains("tiff") { return .tiff }
        if normalized.contains("gif") { return .gif }
        if normalized.contains("webp") { return .webp }
        if normalized.contains("bmp") { return .bmp }
        if normalized.contains("pdf") { return .pdf }
        if normalized.contains("raw") || normalized.contains("dng") || normalized.contains("cr2") || normalized.contains("nef") { return .raw }
        return .unknown
    }
}

public struct ImageDocument: Identifiable, Hashable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let nameWithoutExtension: String
    public let fileExtension: String
    public let width: Int
    public let height: Int
    public let fileSizeBytes: Int64
    public let format: ImageFormat
    public let colorSpace: String?
    public let dpiWidth: Double?
    public let dpiHeight: Double?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let exif: ExifMetadata

    public init(url: URL) throws {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageDocumentError.cannotOpenFile(url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let width = Self.rotatesDimensions(for: orientation) ? rawHeight : rawWidth
        let height = Self.rotatesDimensions(for: orientation) ? rawWidth : rawHeight
        let colorSpace = properties[kCGImagePropertyColorModel] as? String
        let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
        let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue

        let exifDictionary = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exif = ExifMetadata(
            cameraModel: properties[kCGImagePropertyTIFFModel] as? String,
            focalLength: (exifDictionary[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue,
            aperture: (exifDictionary[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            iso: {
                guard let array = exifDictionary[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber],
                      let first = array.first else { return nil }
                return first.intValue
            }(),
            shutterSpeed: (exifDictionary[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue
        )

        let typeIdentifier = CGImageSourceGetType(source) as String?

        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.nameWithoutExtension = url.deletingPathExtension().lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.width = width
        self.height = height
        self.fileSizeBytes = fileSize
        self.format = ImageFormat.from(typeIdentifier: typeIdentifier)
        self.colorSpace = colorSpace
        self.dpiWidth = dpiWidth
        self.dpiHeight = dpiHeight
        self.createdAt = resourceValues.creationDate
        self.modifiedAt = resourceValues.contentModificationDate
        self.exif = exif
    }

    public var dimensionsLabel: String {
        "\(width) × \(height) px"
    }

    public var humanReadableFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }

    private static func rotatesDimensions(for orientation: Int) -> Bool {
        switch orientation {
        case 5, 6, 7, 8:
            return true
        default:
            return false
        }
    }
}

public enum ImageDocumentError: Error, Equatable, Sendable {
    case cannotOpenFile(URL)
}
