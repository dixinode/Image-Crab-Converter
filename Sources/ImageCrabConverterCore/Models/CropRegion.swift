import CoreGraphics
import Foundation

public struct CropRegion: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public func clamped(to imageSize: CGSize) -> CropRegion {
        let clampedX = min(max(0, x), max(0, imageSize.width - 1))
        let clampedY = min(max(0, y), max(0, imageSize.height - 1))
        let clampedWidth = min(max(1, width), imageSize.width - clampedX)
        let clampedHeight = min(max(1, height), imageSize.height - clampedY)
        return CropRegion(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }
}
