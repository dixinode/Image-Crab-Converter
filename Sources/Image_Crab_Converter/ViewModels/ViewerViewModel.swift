import AppKit
import CoreGraphics
import Foundation
import ImageCrabConverterCore
import ImageIO
import SwiftUI

@MainActor
final class ViewerViewModel: ObservableObject {
    @Published var currentDocument: ImageDocument?
    @Published var currentImage: NSImage?
    @Published var currentZoom: CGFloat = 1.0
    @Published var isResizeSheetPresented = false
    @Published var resizeWidth = "1920"
    @Published var resizeHeight = "1080"
    @Published var resizeWidthPercent = "100"
    @Published var resizeHeightPercent = "100"
    @Published var resizeLockAspect = true
    @Published var resizeMethod: ResampleMethod = .lanczos
    @Published var errorMessage: String?
    @Published var canvasSize: CGSize = .zero
    @Published var isCropModePresented = false
    @Published var isCanvasOnlyMode = false
    @Published var cropSelectionNormalized = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @Published var scrollOffset: CGPoint = .zero
    @Published private(set) var fitRequestID: Int = 0
    
    // Displayed image dimensions after orientation is applied.
    private var displayImageWidth: CGFloat = 0
    private var displayImageHeight: CGFloat = 0

    private let zoomIncrementPercent: CGFloat = 5
    private let minZoom: CGFloat = 0.01
    private let maxZoom: CGFloat = 32.0

    /// Full image rect in canvas (viewport) coordinates, accounting for zoom and scroll.
    /// May extend beyond canvas bounds when zoomed in.
    var imageDisplayFrame: CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }
        let dispW = displayImageWidth * currentZoom
        let dispH = displayImageHeight * currentZoom
        let containerW = max(dispW, canvasSize.width)
        let containerH = max(dispH, canvasSize.height)
        let scrollX = isCropModePresented ? 0.0 : scrollOffset.x
        let scrollY = isCropModePresented ? 0.0 : scrollOffset.y
        let originX = (containerW - dispW) / 2 - scrollX
        let originY = (containerH - dispH) / 2 - scrollY
        return CGRect(x: originX, y: originY, width: dispW, height: dispH)
    }

    var currentImagePixelSize: CGSize {
        guard displayImageWidth > 0, displayImageHeight > 0 else {
            guard let document = currentDocument else { return .zero }
            return CGSize(width: document.width, height: document.height)
        }

        return CGSize(width: displayImageWidth, height: displayImageHeight)
    }

    var hasCurrentImage: Bool {
        currentDocument != nil && currentImage != nil
    }

    private var folderImages: [URL] = []
    private var currentIndex = 0
    private let imageProcessor = ImageProcessor()
    private var pendingFitAfterOpen = false
    private var pendingFitAfterLayoutChange = false
    private var savedZoomBeforeCrop: CGFloat?


    

    
    func openImage(url: URL) {
        do {
            let document = try ImageDocument(url: url)
            let cgImage = try imageProcessor.loadImage(at: url)
            let displaySize = CGSize(width: cgImage.width, height: cgImage.height)

            currentDocument = document
            currentImage = NSImage(cgImage: cgImage, size: displaySize)
            displayImageWidth = displaySize.width
            displayImageHeight = displaySize.height
            errorMessage = nil

            updateWindowTitle()
            refreshWindowTitleSoon()
            isCropModePresented = false
            scrollOffset = .zero
            loadSiblingImages(for: url)
            currentIndex = folderImages.firstIndex(of: url) ?? 0

            resizeWidthPercent = "100"
            resizeHeightPercent = "100"
            resizeWidth = String(document.width)
            resizeHeight = String(document.height)

            pendingFitAfterOpen = true

            applyPendingFitIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingFitIfNeeded()
            }
        } catch {
            errorMessage = "Failed to open image: \(error.localizedDescription)"
        }
    }

    func updateCanvasSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard abs(canvasSize.width - size.width) > 0.5 || abs(canvasSize.height - size.height) > 0.5 else {
            return
        }
        canvasSize = size
        applyPendingFitIfNeeded()
    }

    func updateScrollOffset(_ point: CGPoint) {
        guard abs(scrollOffset.x - point.x) > 0.5 || abs(scrollOffset.y - point.y) > 0.5 else {
            return
        }
        scrollOffset = point
    }

    func nextImage() {
        guard !folderImages.isEmpty else { return }
        currentIndex = min(folderImages.count - 1, currentIndex + 1)
        openImage(url: folderImages[currentIndex])
    }

    func previousImage() {
        guard !folderImages.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
        openImage(url: folderImages[currentIndex])
    }

    func zoomIn() {
        let currentPercent = currentZoom * 100
        let epsilon: CGFloat = 0.0001
        var nextPercent = (floor((currentPercent + epsilon) / zoomIncrementPercent) + 1) * zoomIncrementPercent
        if nextPercent <= currentPercent + epsilon {
            nextPercent += zoomIncrementPercent
        }
        setZoom(nextPercent / 100, animated: true)
    }

    func zoomOut() {
        let currentPercent = currentZoom * 100
        let epsilon: CGFloat = 0.0001
        var previousPercent = (ceil((currentPercent - epsilon) / zoomIncrementPercent) - 1) * zoomIncrementPercent
        if previousPercent >= currentPercent - epsilon {
            previousPercent -= zoomIncrementPercent
        }
        setZoom(previousPercent / 100, animated: true)
    }

    func zoomToActual() {
        setZoom(1.0, animated: true)
    }

    func toggleCanvasFullscreen() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow

        if let window, window.styleMask.contains(.fullScreen), isCanvasOnlyMode {
            requestFitOnNextLayoutChange()
            isCanvasOnlyMode = false
            applyWindowChrome()
            window.toggleFullScreen(nil)
            return
        }

        requestFitOnNextLayoutChange()
        isCanvasOnlyMode = true
        applyWindowChrome()

        if let window, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }

        DispatchQueue.main.async { [weak self] in
            self?.applyWindowChrome()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.applyWindowChrome()
        }
    }

    func applyWindowChrome() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        window.titleVisibility = isCanvasOnlyMode ? .hidden : .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = isCanvasOnlyMode ? .black : .windowBackgroundColor
        window.styleMask.insert(.fullSizeContentView)

        window.toolbar?.isVisible = !isCanvasOnlyMode

        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { buttonType in
            window.standardWindowButton(buttonType)?.isHidden = isCanvasOnlyMode
        }

        updateWindowTitle()
    }

    func setZoomPercent(_ percent: Double) {
        setZoom(CGFloat(percent) / 100, animated: false)
    }

    func fitToWindow(animated: Bool = true) {
        let imageWidth = displayImageWidth
        let imageHeight = displayImageHeight

        guard imageWidth > 0, imageHeight > 0 else {
            return
        }

        let availableWidth = max(canvasSize.width, 1)
        let availableHeight = max(canvasSize.height, 1)
        guard availableWidth > 0, availableHeight > 0 else {
            return
        }

        let fitScale = min(availableWidth / imageWidth, availableHeight / imageHeight)
        scrollOffset = .zero
        fitRequestID &+= 1
        setZoom(fitScale, animated: animated)
    }

    func requestFitOnNextLayoutChange() {
        guard currentImage != nil else { return }
        pendingFitAfterLayoutChange = true
        scrollOffset = .zero
        applyPendingFitIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingFitIfNeeded()
        }
    }

    func deleteCurrentImage() {
        guard let document = currentDocument else { return }

        let currentURL = document.url
        let remainingImages = folderImages.filter { $0 != currentURL }
        let nextIndex = min(currentIndex, max(remainingImages.count - 1, 0))

        do {
            try FileManager.default.trashItem(at: currentURL, resultingItemURL: nil)
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
            return
        }

        isCropModePresented = false
        isResizeSheetPresented = false
        pendingFitAfterOpen = false
        pendingFitAfterLayoutChange = false

        if remainingImages.isEmpty {
            clearCurrentImage()
            return
        }

        folderImages = remainingImages
        currentIndex = nextIndex
        openImage(url: remainingImages[nextIndex])
    }

    func openCropTool() {
        guard currentDocument != nil else { return }
        if !isCropModePresented {
            savedZoomBeforeCrop = currentZoom
            fitToWindow(animated: true)
            scrollOffset = .zero
            cropSelectionNormalized = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        }
        isCropModePresented = true
    }

    func cancelCropTool() {
        isCropModePresented = false
        if let saved = savedZoomBeforeCrop {
            setZoom(saved, animated: true)
            savedZoomBeforeCrop = nil
        }
    }

    func applyCropSelection() {
        guard let document = currentDocument else { return }

        do {
            let sourceImage = try imageProcessor.loadImage(at: document.url)
            let imageWidth = CGFloat(sourceImage.width)
            let imageHeight = CGFloat(sourceImage.height)
            let normalized = sanitizeCropSelection(cropSelectionNormalized)

            let cropX = normalized.minX * imageWidth
            let cropY = normalized.minY * imageHeight
            let cropWidth = normalized.width * imageWidth
            let cropHeight = normalized.height * imageHeight

            let cropRegion = CropRegion(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
            let croppedImage = try imageProcessor.crop(image: sourceImage, region: cropRegion)

            let outputType = try imageProcessor.resolveOutputType(
                output: .sameAsSource,
                sourceFormat: document.format,
                explicitExtension: document.fileExtension
            )

            let croppedURL = timestampedURL(base: document.url, suffix: "_cropped_", ext: outputType.fileExtension)

            try imageProcessor.write(
                image: croppedImage,
                to: croppedURL,
                typeIdentifier: outputType.typeIdentifier,
                quality: 85
            )

            cropSelectionNormalized = normalized
            isCropModePresented = false
            savedZoomBeforeCrop = nil
            openImage(url: croppedURL)
        } catch {
            errorMessage = "Crop failed: \(error.localizedDescription)"
        }
    }

    func updateResizeFromPixels() {
        guard let document = currentDocument,
              document.width > 0,
              document.height > 0 else {
            return
        }

        let clampedWidth = clampPixelInput(resizeWidth, fallback: document.width)
        let clampedHeight = clampPixelInput(resizeHeight, fallback: document.height)

        resizeWidth = String(clampedWidth)
        resizeHeight = String(clampedHeight)
        resizeWidthPercent = String(pixelToPercent(clampedWidth, of: document.width))
        resizeHeightPercent = String(pixelToPercent(clampedHeight, of: document.height))
    }

    func updateResizeWidthFromPixels() {
        guard let document = currentDocument,
              document.width > 0,
              document.height > 0 else {
            return
        }

        let clampedWidth = clampPixelInput(resizeWidth, fallback: document.width)
        resizeWidth = String(clampedWidth)
        resizeWidthPercent = String(pixelToPercent(clampedWidth, of: document.width))

        if resizeLockAspect {
            syncHeightFromWidth(clampedWidth, docWidth: document.width, docHeight: document.height)
        }
    }

    func updateResizeHeightFromPixels() {
        guard let document = currentDocument,
              document.width > 0,
              document.height > 0 else {
            return
        }

        let clampedHeight = clampPixelInput(resizeHeight, fallback: document.height)
        resizeHeight = String(clampedHeight)
        resizeHeightPercent = String(pixelToPercent(clampedHeight, of: document.height))

        if resizeLockAspect {
            syncWidthFromHeight(clampedHeight, docWidth: document.width, docHeight: document.height)
        }
    }

    func updateResizeFromPercent() {
        guard let document = currentDocument,
              let widthPercent = Double(resizeWidthPercent),
              let heightPercent = Double(resizeHeightPercent),
              document.width > 0,
              document.height > 0 else {
            return
        }

        let newWidth = Int(Double(document.width) * widthPercent / 100)
        resizeWidth = String(newWidth)

        if resizeLockAspect {
            syncHeightFromWidth(newWidth, docWidth: document.width, docHeight: document.height)
        } else {
            resizeHeight = String(Int(Double(document.height) * heightPercent / 100))
        }
    }

    func updateResizeWidthPercent() {
        guard let document = currentDocument,
              document.width > 0 else {
            return
        }

        let clampedPercent = clampPercentInput(resizeWidthPercent)
        resizeWidthPercent = String(clampedPercent)

        let clampedWidth = max(1, Int(Double(document.width) * Double(clampedPercent) / 100))
        resizeWidth = String(clampedWidth)

        if resizeLockAspect, document.height > 0 {
            syncHeightFromWidth(clampedWidth, docWidth: document.width, docHeight: document.height)
        }
    }

    func updateResizeHeightPercent() {
        guard let document = currentDocument,
              document.height > 0 else {
            return
        }

        let clampedPercent = clampPercentInput(resizeHeightPercent)
        resizeHeightPercent = String(clampedPercent)

        let clampedHeight = max(1, Int(Double(document.height) * Double(clampedPercent) / 100))
        resizeHeight = String(clampedHeight)

        if resizeLockAspect, document.width > 0 {
            syncWidthFromHeight(clampedHeight, docWidth: document.width, docHeight: document.height)
        }
    }

    // MARK: - Resize Helpers

    private func clampPixelInput(_ text: String, fallback: Int) -> Int {
        max(1, Int(text.filter { $0.isNumber }) ?? fallback)
    }

    private func clampPercentInput(_ text: String) -> Int {
        let digits = text.replacingOccurrences(of: "%", with: "").filter { $0.isNumber }
        return min(max(Int(digits) ?? 100, 1), 10000)
    }

    private func pixelToPercent(_ pixels: Int, of original: Int) -> Int {
        Int((Double(pixels) / Double(original) * 100).rounded())
    }

    private func syncHeightFromWidth(_ width: Int, docWidth: Int, docHeight: Int) {
        let aspectRatio = Double(docHeight) / Double(docWidth)
        let calculatedHeight = max(1, Int(Double(width) * aspectRatio))
        resizeHeight = String(calculatedHeight)
        resizeHeightPercent = String(pixelToPercent(calculatedHeight, of: docHeight))
    }

    private func syncWidthFromHeight(_ height: Int, docWidth: Int, docHeight: Int) {
        let aspectRatio = Double(docWidth) / Double(docHeight)
        let calculatedWidth = max(1, Int(Double(height) * aspectRatio))
        resizeWidth = String(calculatedWidth)
        resizeWidthPercent = String(pixelToPercent(calculatedWidth, of: docWidth))
    }

    private func timestampedURL(base: URL, suffix: String, ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH_mm_ss"
        let timestamp = formatter.string(from: Date())
        return base.deletingLastPathComponent()
            .appendingPathComponent(base.deletingPathExtension().lastPathComponent + suffix + timestamp)
            .appendingPathExtension(ext)
    }
    
    func resizeCurrentImage() {
        guard let document = currentDocument else {
            return
        }
        
        let width = clampPixelInput(resizeWidth, fallback: document.width)
        let height = clampPixelInput(resizeHeight, fallback: document.height)

        do {
            let job = BatchJob(
                rename: RenameOptions(enabled: false),
                resize: ResizeOptions(
                    enabled: true,
                    width: width,
                    height: height,
                    maintainAspectRatio: resizeLockAspect,
                    method: resizeMethod,
                    resizeOnlyIfLarger: false
                ),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .sameAsSource, quality: 85, destination: .sameAsSource, subfolderName: nil)
            )

            let resizedURL = timestampedURL(base: document.url, suffix: "_", ext: document.fileExtension)

            try imageProcessor.processFile(sourceURL: document.url, sourceFormat: document.format, job: job, outputURL: resizedURL)
            openImage(url: resizedURL)
            isResizeSheetPresented = false
        } catch {
            errorMessage = "Resize failed: \(error.localizedDescription)"
        }
    }

    private func loadSiblingImages(for url: URL) {
        let folderURL = url.deletingLastPathComponent()
        let allowed = Set(["jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp", "webp"])

        do {
            let urls = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            folderImages = urls
                .filter { allowed.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            folderImages = [url]
        }
    }

    private func applyPendingFitIfNeeded() {
        guard pendingFitAfterOpen || pendingFitAfterLayoutChange else {
            return
        }

        guard canvasSize.width > 10, canvasSize.height > 10,
              displayImageWidth > 0, displayImageHeight > 0 else {
            return
        }

        pendingFitAfterOpen = false
        pendingFitAfterLayoutChange = false
        fitToWindow(animated: false)
    }

    private func clearCurrentImage() {
        currentDocument = nil
        currentImage = nil
        displayImageWidth = 0
        displayImageHeight = 0
        currentZoom = 1.0
        scrollOffset = .zero
        cropSelectionNormalized = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        folderImages = []
        currentIndex = 0
        updateWindowTitle()
    }

    private func sanitizeCropSelection(_ rect: CGRect) -> CGRect {
        let minWidth: CGFloat = 0.01
        let minHeight: CGFloat = 0.01

        var left = min(max(rect.minX, 0), 1)
        var top = min(max(rect.minY, 0), 1)
        var right = min(max(rect.maxX, 0), 1)
        var bottom = min(max(rect.maxY, 0), 1)

        if right - left < minWidth {
            right = min(1, left + minWidth)
            left = max(0, right - minWidth)
        }

        if bottom - top < minHeight {
            bottom = min(1, top + minHeight)
            top = max(0, bottom - minHeight)
        }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func setZoom(_ value: CGFloat, animated: Bool) {
        let clamped = min(max(value, minZoom), maxZoom)
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                currentZoom = clamped
            }
        } else {
            currentZoom = clamped
        }
    }

    private func refreshWindowTitleSoon() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWindowTitle()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateWindowTitle()
        }
    }

    private func updateWindowTitle() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        window.titleVisibility = isCanvasOnlyMode ? .hidden : .visible

        if let document = currentDocument {
            window.title = document.url.path
            window.representedURL = document.url
        } else {
            window.title = "Image_Crab_Converter"
            window.representedURL = nil
        }
    }
}
