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
}
