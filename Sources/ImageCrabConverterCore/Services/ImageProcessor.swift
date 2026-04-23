import AppKit
import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageProcessorError: Error, Equatable, Sendable {
    case loadFailed(URL)
    case cropFailed
    case resizeFailed
    case destinationCreateFailed(URL)
    case writeFailed(URL)
    case unsupportedOutputFormat(String)
}

public struct ImageProcessor: Sendable {
    private static let supportedDestinationTypeIdentifiers: Set<String> = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as NSArray? as? [String] ?? []
        return Set(identifiers)
    }()

    public init() {}

    public static func supportsOutputFormat(_ format: OutputFormat) -> Bool {
        switch format {
        case .sameAsSource:
            return true
        case .jpeg:
            return supportsDestinationType(UTType.jpeg.identifier)
        case .png:
            return supportsDestinationType(UTType.png.identifier)
        case .tiff:
            return supportsDestinationType(UTType.tiff.identifier)
        case .webp:
            guard let type = UTType(filenameExtension: "webp") else {
                return false
            }
            return supportsDestinationType(type.identifier)
        }
    }

    public static func supportedExplicitOutputFormats() -> [OutputFormat] {
        OutputFormat.allCases.filter { $0 != .sameAsSource && supportsOutputFormat($0) }
    }

    public func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageProcessorError.loadFailed(url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exifOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1

        guard let orientedImage = orientedImage(image, exifOrientation: exifOrientation) else {
            throw ImageProcessorError.loadFailed(url)
        }

        return orientedImage
    }

    public func resize(image: CGImage, to targetSize: CGSize, method: ResampleMethod) throws -> CGImage {
        let width = max(Int(targetSize.width.rounded()), 1)
        let height = max(Int(targetSize.height.rounded()), 1)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageProcessorError.resizeFailed
        }

        switch method {
        case .lanczos:
            context.interpolationQuality = .high
        case .bilinear:
            context.interpolationQuality = .medium
        case .nearestNeighbor:
            context.interpolationQuality = .none
        }

        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))

        guard let resized = context.makeImage() else {
            throw ImageProcessorError.resizeFailed
        }

        return resized
    }

    public func crop(image: CGImage, region: CropRegion) throws -> CGImage {
        let clamped = region.clamped(to: CGSize(width: image.width, height: image.height)).rect.integral
        guard let cropped = image.cropping(to: clamped) else {
            throw ImageProcessorError.cropFailed
        }
        return cropped
    }

    public func cropRegion(for imageSize: CGSize, options: CropOptions) -> CropRegion {
        let imageWidth = max(1, imageSize.width)
        let imageHeight = max(1, imageSize.height)

        let cropSize: CGSize = {
            switch options.mode {
            case let .fixedSize(width, height):
                return CGSize(width: min(CGFloat(max(width, 1)), imageWidth), height: min(CGFloat(max(height, 1)), imageHeight))
            case let .aspectRatio(width, height):
                let targetRatio = CGFloat(max(width, 1)) / CGFloat(max(height, 1))
                let imageRatio = imageWidth / imageHeight

                if imageRatio > targetRatio {
                    return CGSize(width: imageHeight * targetRatio, height: imageHeight)
                }
                return CGSize(width: imageWidth, height: imageWidth / targetRatio)
            }
        }()

        let remainingWidth = max(0, imageWidth - cropSize.width)
        let remainingHeight = max(0, imageHeight - cropSize.height)

        let originX: CGFloat
        switch options.anchor {
        case .topLeft, .middleLeft, .bottomLeft:
            originX = 0
        case .topCenter, .middleCenter, .bottomCenter:
            originX = remainingWidth / 2
        case .topRight, .middleRight, .bottomRight:
            originX = remainingWidth
        }

        let originY: CGFloat
        switch options.anchor {
        case .topLeft, .topCenter, .topRight:
            originY = 0
        case .middleLeft, .middleCenter, .middleRight:
            originY = remainingHeight / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            originY = remainingHeight
        }

        return CropRegion(x: originX, y: originY, width: cropSize.width, height: cropSize.height)
    }

    public func resizedDimensions(
        originalWidth: Int,
        originalHeight: Int,
        resizeOptions: ResizeOptions
    ) -> CGSize {
        let originalWidth = max(1, originalWidth)
        let originalHeight = max(1, originalHeight)

        if resizeOptions.scaleMode == .percent {
            let widthPercent = max(1, resizeOptions.widthPercent)
            let heightPercent = max(1, resizeOptions.heightPercent)

            if resizeOptions.maintainAspectRatio {
                let scale = Double(widthPercent) / 100.0
                let width = max(1, Int((Double(originalWidth) * scale).rounded()))
                let height = max(1, Int((Double(originalHeight) * scale).rounded()))
                return CGSize(width: width, height: height)
            }

            let width = max(1, Int((Double(originalWidth) * Double(widthPercent) / 100.0).rounded()))
            let height = max(1, Int((Double(originalHeight) * Double(heightPercent) / 100.0).rounded()))
            return CGSize(width: width, height: height)
        }

        if resizeOptions.maintainAspectRatio {
            let targetWidth = max(1, resizeOptions.width)
            let ratio = Double(originalHeight) / Double(originalWidth)
            let calculatedHeight = max(1, Int((Double(targetWidth) * ratio).rounded()))
            return CGSize(width: targetWidth, height: calculatedHeight)
        }

        return CGSize(width: max(1, resizeOptions.width), height: max(1, resizeOptions.height))
    }

    public func processFile(
        sourceURL: URL,
        sourceFormat: ImageFormat,
        job: BatchJob,
        outputURL: URL
    ) throws {
        var image = try loadImage(at: sourceURL)

        if job.crop.enabled {
            let region = cropRegion(
                for: CGSize(width: image.width, height: image.height),
                options: job.crop
            )
            image = try crop(image: image, region: region)
        }

        if job.resize.enabled {
            let targetSize = resizedDimensions(
                originalWidth: image.width,
                originalHeight: image.height,
                resizeOptions: job.resize
            )

            let shouldSkip = job.resize.resizeOnlyIfLarger && image.width <= Int(targetSize.width) && image.height <= Int(targetSize.height)
            if !shouldSkip {
                image = try resize(image: image, to: targetSize, method: job.resize.method)
            }
        }

        let output = try resolveOutputType(output: job.output.format, sourceFormat: sourceFormat, explicitExtension: outputURL.pathExtension)
        try write(image: image, to: outputURL, typeIdentifier: output.typeIdentifier, quality: job.output.quality)
    }

    public func resolveOutputType(
        output: OutputFormat,
        sourceFormat: ImageFormat,
        explicitExtension: String? = nil
    ) throws -> (typeIdentifier: CFString, fileExtension: String) {
        let normalizedExplicit = explicitExtension?.lowercased()
        if let normalizedExplicit, !normalizedExplicit.isEmpty {
            if let type = UTType(filenameExtension: normalizedExplicit) {
                guard Self.supportsDestinationType(type.identifier) else {
                    throw ImageProcessorError.unsupportedOutputFormat(normalizedExplicit.uppercased())
                }
                return (type.identifier as CFString, normalizedExplicit)
            }
        }

        switch output {
        case .jpeg:
            return try supportedOutputType(type: UTType.jpeg, fallbackExtension: "jpg", name: "JPEG")
        case .png:
            return try supportedOutputType(type: UTType.png, fallbackExtension: "png", name: "PNG")
        case .tiff:
            return try supportedOutputType(type: UTType.tiff, fallbackExtension: "tiff", name: "TIFF")
        case .webp:
            if let webpType = UTType(filenameExtension: "webp"), Self.supportsDestinationType(webpType.identifier) {
                return (webpType.identifier as CFString, "webp")
            }
            throw ImageProcessorError.unsupportedOutputFormat("WebP")
        case .sameAsSource:
            switch sourceFormat {
            case .jpeg:
                return (UTType.jpeg.identifier as CFString, "jpg")
            case .png:
                return (UTType.png.identifier as CFString, "png")
            case .tiff:
                return (UTType.tiff.identifier as CFString, "tiff")
            case .webp:
                if let webpType = UTType(filenameExtension: "webp"), Self.supportsDestinationType(webpType.identifier) {
                    return (webpType.identifier as CFString, "webp")
                }
                return (UTType.png.identifier as CFString, "png")
            case .heic:
                if #available(macOS 11.0, *) {
                    return (UTType.heic.identifier as CFString, "heic")
                }
                return (UTType.jpeg.identifier as CFString, "jpg")
            case .gif:
                return (UTType.gif.identifier as CFString, "gif")
            case .bmp:
                return (UTType.bmp.identifier as CFString, "bmp")
            case .pdf:
                return (UTType.png.identifier as CFString, "png")
            case .raw, .unknown:
                return (UTType.png.identifier as CFString, "png")
            }
        }
    }

    public func write(
        image: CGImage,
        to url: URL,
        typeIdentifier: CFString,
        quality: Int
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier, 1, nil) else {
            throw ImageProcessorError.destinationCreateFailed(url)
        }

        let qualityValue = max(1, min(100, quality))
        let options = [kCGImageDestinationLossyCompressionQuality: NSNumber(value: Double(qualityValue) / 100.0)] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.writeFailed(url)
        }
    }

    private func orientedImage(_ image: CGImage, exifOrientation: Int) -> CGImage? {
        guard exifOrientation != 1 else {
            return image
        }

        let ciImage = CIImage(cgImage: image).oriented(forExifOrientation: Int32(exifOrientation))
        return CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent.integral)
    }

    private static func supportsDestinationType(_ identifier: String) -> Bool {
        supportedDestinationTypeIdentifiers.contains(identifier)
    }

    private func supportedOutputType(type: UTType, fallbackExtension: String, name: String) throws -> (typeIdentifier: CFString, fileExtension: String) {
        guard Self.supportsDestinationType(type.identifier) else {
            throw ImageProcessorError.unsupportedOutputFormat(name)
        }
        return (type.identifier as CFString, fallbackExtension)
    }
}
