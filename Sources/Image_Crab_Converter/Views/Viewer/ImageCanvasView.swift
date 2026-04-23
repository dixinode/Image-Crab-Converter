import AppKit
import SwiftUI

@MainActor
struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage?
    let zoom: CGFloat
    let fitRequestID: Int
    let viewportSize: CGSize
    var onScrollChanged: ((CGPoint) -> Void)?
    var onViewportChanged: ((CGSize) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CanvasScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = false

        let coordinator = context.coordinator
        let containerView = coordinator.containerView
        let imageView = coordinator.imageView
        imageView.translatesAutoresizingMaskIntoConstraints = true
        containerView.addSubview(imageView)
        scrollView.documentView = containerView

        scrollView.onScrollOffsetChanged = { origin in
            coordinator.onScrollChanged?(origin)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onScrollChanged = onScrollChanged

        let rawClipSize = nsView.contentView.bounds.size
        if rawClipSize.width > 0, rawClipSize.height > 0,
           context.coordinator.lastReportedViewportSize != rawClipSize {
            context.coordinator.lastReportedViewportSize = rawClipSize
            onViewportChanged?(rawClipSize)
        }

        let containerView = context.coordinator.containerView
        let imageView = context.coordinator.imageView
        imageView.image = image
        let effectiveClipSize: CGSize
        if rawClipSize.width > 0, rawClipSize.height > 0 {
            effectiveClipSize = rawClipSize
        } else {
            effectiveClipSize = viewportSize
        }

        let clipSize = CGSize(
            width: max(effectiveClipSize.width, 1),
            height: max(effectiveClipSize.height, 1)
        )

        guard let image else {
            imageView.frame = .zero
            containerView.frame = NSRect(origin: .zero, size: clipSize)
            context.coordinator.lastImageID = nil
            return
        }

        let imageChanged: Bool = {
            let newID = ObjectIdentifier(image)
            defer { context.coordinator.lastImageID = newID }
            return context.coordinator.lastImageID != newID
        }()

        let zoomChanged = context.coordinator.lastZoom != zoom
        let viewportChanged = context.coordinator.lastViewportSize != viewportSize
        let fitRequestChanged = context.coordinator.lastFitRequestID != fitRequestID
        context.coordinator.lastZoom = zoom
        context.coordinator.lastViewportSize = viewportSize
        context.coordinator.lastFitRequestID = fitRequestID

        guard imageChanged || zoomChanged || viewportChanged || fitRequestChanged else { return }

        let clipBounds = NSRect(origin: nsView.contentView.bounds.origin, size: clipSize)
        let oldFrame = containerView.frame
        let visibleRect = nsView.contentView.documentVisibleRect

        let centerRatioX: CGFloat
        let centerRatioY: CGFloat
        if !imageChanged, !fitRequestChanged, oldFrame.width > 0, oldFrame.height > 0 {
            centerRatioX = visibleRect.midX / oldFrame.width
            centerRatioY = visibleRect.midY / oldFrame.height
        } else {
            centerRatioX = 0.5
            centerRatioY = 0.5
        }

        let baseSize = context.coordinator.pixelSize(for: image)
        let imageWidth = max(1, baseSize.width * zoom)
        let imageHeight = max(1, baseSize.height * zoom)
        let containerWidth = max(imageWidth, clipBounds.width)
        let containerHeight = max(imageHeight, clipBounds.height)

        containerView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
        imageView.frame = NSRect(
            x: (containerWidth - imageWidth) / 2,
            y: (containerHeight - imageHeight) / 2,
            width: imageWidth,
            height: imageHeight
        )
        imageView.dragPanningEnabled = imageWidth > clipBounds.width || imageHeight > clipBounds.height

        nsView.magnification = 1.0
        nsView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let targetCenterX = containerWidth * centerRatioX
        let targetCenterY = containerHeight * centerRatioY
        let targetOriginX = targetCenterX - clipBounds.width / 2
        let targetOriginY = targetCenterY - clipBounds.height / 2
        let maxOriginX = max(0, containerWidth - clipBounds.width)
        let maxOriginY = max(0, containerHeight - clipBounds.height)

        let clampedOrigin = NSPoint(
            x: min(max(targetOriginX, 0), maxOriginX),
            y: min(max(targetOriginY, 0), maxOriginY)
        )

        if fitRequestChanged {
            centerScrollView(nsView, at: centeredOrigin(for: nsView))
        } else {
            centerScrollView(nsView, at: clampedOrigin)
        }

        if imageChanged || fitRequestChanged {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                centerScrollView(nsView, at: centeredOrigin(for: nsView))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                centerScrollView(nsView, at: centeredOrigin(for: nsView))
            }
        }
    }

    private func centerScrollView(_ scrollView: NSScrollView, at origin: NSPoint) {
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func centeredOrigin(for scrollView: NSScrollView) -> NSPoint {
        let clip = scrollView.contentView.bounds.size
        let doc = scrollView.documentView?.bounds.size ?? .zero
        let originX = max(0, (doc.width - clip.width) / 2)
        let originY = max(0, (doc.height - clip.height) / 2)
        return NSPoint(x: originX, y: originY)
    }

    @MainActor
    final class Coordinator {
        let containerView = CanvasContainerView()
        let imageView = ZoomImageView()
        var lastImageID: ObjectIdentifier?
        var lastZoom: CGFloat = -1
        var lastViewportSize: CGSize = .zero
        var lastFitRequestID: Int = -1
        var lastReportedViewportSize: CGSize = .zero
        var onScrollChanged: ((CGPoint) -> Void)?

        func pixelSize(for image: NSImage) -> CGSize {
            if image.size.width > 0, image.size.height > 0 {
                return image.size
            }

            for rep in image.representations {
                if rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
                    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                }
            }

            return image.size
        }
    }
}

@MainActor
final class CanvasScrollView: NSScrollView {
    var onScrollOffsetChanged: ((CGPoint) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func reflectScrolledClipView(_ aClipView: NSClipView) {
        super.reflectScrolledClipView(aClipView)
        onScrollOffsetChanged?(contentView.bounds.origin)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    // Navigation keys (Space, ←, →) are handled centrally by AppDelegate
    // via NotificationCenter to avoid double-firing.
}

@MainActor
final class CanvasContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ZoomImageView: NSView {
    var image: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    var dragPanningEnabled = false {
        didSet {
            if oldValue != dragPanningEnabled {
                discardCursorRects()
            }
        }
    }

    private var panStartPoint: NSPoint?
    private var panStartOrigin: NSPoint = .zero
    private var didPushClosedHandCursor = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        if dragPanningEnabled {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard dragPanningEnabled,
              let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else {
            super.mouseDown(with: event)
            return
        }

        panStartPoint = convert(event.locationInWindow, from: nil)
        panStartOrigin = scrollView.contentView.bounds.origin
        if !didPushClosedHandCursor {
            NSCursor.closedHand.push()
            didPushClosedHandCursor = true
        }

        if documentView.bounds.width <= scrollView.contentView.bounds.width,
           documentView.bounds.height <= scrollView.contentView.bounds.height {
            panStartPoint = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragPanningEnabled,
              let panStartPoint,
              let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else {
            super.mouseDragged(with: event)
            return
        }

        let current = convert(event.locationInWindow, from: nil)
        let deltaX = current.x - panStartPoint.x
        let deltaY = current.y - panStartPoint.y

        let clip = scrollView.contentView.bounds.size
        let doc = documentView.bounds.size
        let maxX = max(0, doc.width - clip.width)
        let maxY = max(0, doc.height - clip.height)

        let target = NSPoint(
            x: min(max(panStartOrigin.x - deltaX, 0), maxX),
            y: min(max(panStartOrigin.y - deltaY, 0), maxY)
        )

        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        panStartPoint = nil
        if didPushClosedHandCursor {
            NSCursor.pop()
            didPushClosedHandCursor = false
        }
        super.mouseUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.interpolationQuality = .high
        context.clear(bounds)

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(origin: .zero, size: bounds.size))
        } else {
            image.draw(in: bounds)
        }

        context.restoreGState()
    }
}
