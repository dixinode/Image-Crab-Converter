import CoreGraphics
import Foundation

public enum ResampleMethod: String, CaseIterable, Sendable {
    case lanczos = "Lanczos"
    case bilinear = "Bilinear"
    case nearestNeighbor = "Nearest Neighbor"
}

public enum ResizeScaleMode: String, Equatable, Sendable {
    case pixels
    case percent
}

public enum OutputFormat: String, CaseIterable, Sendable {
    case sameAsSource = "Same as source"
    case jpeg = "JPEG"
    case png = "PNG"
    case tiff = "TIFF"
    case webp = "WebP"

    public var extensionValue: String {
        switch self {
        case .sameAsSource: ""
        case .jpeg: "jpg"
        case .png: "png"
        case .tiff: "tiff"
        case .webp: "webp"
        }
    }
}

public enum AnchorPoint: String, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleCenter
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

public struct RenameOptions: Equatable, Sendable {
    public var enabled: Bool
    public var pattern: String
    public var startNumber: Int

    public init(enabled: Bool = false, pattern: String = "IMG_{n:3}_{date}.{ext}", startNumber: Int = 1) {
        self.enabled = enabled
        self.pattern = pattern
        self.startNumber = startNumber
    }
}

public struct ResizeOptions: Equatable, Sendable {
    public var enabled: Bool
    public var width: Int
    public var height: Int
    public var widthPercent: Int
    public var heightPercent: Int
    public var maintainAspectRatio: Bool
    public var scaleMode: ResizeScaleMode
    public var method: ResampleMethod
    public var resizeOnlyIfLarger: Bool

    public init(
        enabled: Bool = false,
        width: Int = 1920,
        height: Int = 1080,
        widthPercent: Int = 100,
        heightPercent: Int = 100,
        maintainAspectRatio: Bool = true,
        scaleMode: ResizeScaleMode = .pixels,
        method: ResampleMethod = .lanczos,
        resizeOnlyIfLarger: Bool = false
    ) {
        self.enabled = enabled
        self.width = width
        self.height = height
        self.widthPercent = widthPercent
        self.heightPercent = heightPercent
        self.maintainAspectRatio = maintainAspectRatio
        self.scaleMode = scaleMode
        self.method = method
        self.resizeOnlyIfLarger = resizeOnlyIfLarger
    }
}

public struct CropOptions: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case fixedSize(width: Int, height: Int)
        case aspectRatio(width: Int, height: Int)
    }

    public var enabled: Bool
    public var mode: Mode
    public var anchor: AnchorPoint

    public init(enabled: Bool = false, mode: Mode = .fixedSize(width: 800, height: 600), anchor: AnchorPoint = .middleCenter) {
        self.enabled = enabled
        self.mode = mode
        self.anchor = anchor
    }
}

public enum DestinationFolder: Equatable, Sendable {
    case sameAsSource
    case custom(URL)
}

public struct OutputOptions: Equatable, Sendable {
    public var format: OutputFormat
    public var quality: Int
    public var destination: DestinationFolder
    public var subfolderName: String?

    public init(
        format: OutputFormat = .sameAsSource,
        quality: Int = 85,
        destination: DestinationFolder = .sameAsSource,
        subfolderName: String? = nil
    ) {
        self.format = format
        self.quality = quality
        self.destination = destination
        self.subfolderName = subfolderName
    }
}

public struct BatchJob: Equatable, Sendable {
    public var rename: RenameOptions
    public var resize: ResizeOptions
    public var crop: CropOptions
    public var output: OutputOptions

    public init(
        rename: RenameOptions = .init(),
        resize: ResizeOptions = .init(),
        crop: CropOptions = .init(),
        output: OutputOptions = .init()
    ) {
        self.rename = rename
        self.resize = resize
        self.crop = crop
        self.output = output
    }

    public var hasAnyOperationEnabled: Bool {
        rename.enabled || resize.enabled || crop.enabled
    }
}

public struct BatchProgress: Equatable, Sendable {
    public let currentIndex: Int
    public let totalCount: Int
    public let filename: String

    public init(currentIndex: Int, totalCount: Int, filename: String) {
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.filename = filename
    }
}

public struct BatchFileResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case success
        case failure(String)
        case cancelled
        case skipped(String)
    }

    public let file: URL
    public let outputURL: URL?
    public let status: Status

    public init(file: URL, outputURL: URL?, status: Status) {
        self.file = file
        self.outputURL = outputURL
        self.status = status
    }
}

public struct BatchRunSummary: Equatable, Sendable {
    public let results: [BatchFileResult]

    public init(results: [BatchFileResult]) {
        self.results = results
    }

    public var successCount: Int {
        results.filter { if case .success = $0.status { return true }; return false }.count
    }

    public var failureCount: Int {
        results.filter { if case .failure = $0.status { return true }; return false }.count
    }

    public var cancelledCount: Int {
        results.filter { if case .cancelled = $0.status { return true }; return false }.count
    }
}
