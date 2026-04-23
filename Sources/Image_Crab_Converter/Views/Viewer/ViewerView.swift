import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @ObservedObject var viewModel: ViewerViewModel
    @Binding var isSidebarCollapsed: Bool
    @State private var isImporting = false
    @State private var isDeleteConfirmationPresented = false
    @AppStorage("viewer.useCheckerboardCanvas") private var useCheckerboardCanvas = true
    @State private var keyMonitor: Any?

    private let zoomSliderGamma: Double = 2.2

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isCanvasOnlyMode {
                ViewerToolbarView(
                    viewModel: viewModel,
                    isSidebarCollapsed: $isSidebarCollapsed,
                    useCheckerboardCanvas: $useCheckerboardCanvas
                ) {
                    isImporting = true
                } deleteAction: {
                    isDeleteConfirmationPresented = true
                }
            }

            GeometryReader { geometry in
                ZStack {
                    if viewModel.isCanvasOnlyMode {
                        Rectangle().fill(Color.black)
                    } else if useCheckerboardCanvas {
                        checkerboardBackground
                    } else {
                        Rectangle()
                            .fill(Color.black)
                    }

                    if viewModel.currentImage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 36))
                                .foregroundStyle(CoffeePalette.textTertiary)
                            Text("Open an image to start")
                                .foregroundStyle(CoffeePalette.textSecondary)
                        }
                    } else {
                        ImageCanvasView(
                            image: viewModel.currentImage,
                            zoom: viewModel.currentZoom,
                            fitRequestID: viewModel.fitRequestID,
                            viewportSize: viewModel.canvasSize,
                            onScrollChanged: { viewModel.updateScrollOffset($0) },
                            onViewportChanged: { viewModel.updateCanvasSize($0) }
                        )

                        if viewModel.isCropModePresented {
                            cropOverlay
                        }
                    }
                }
                .onAppear {
                    viewModel.updateCanvasSize(geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewModel.updateCanvasSize(newSize)
                }
            }

            if !viewModel.isCanvasOnlyMode {
                bottomBar
            }
        }
        .background(CoffeePalette.backgroundPrimary)
        .modifier(CanvasOnlyTopSafeArea(enabled: viewModel.isCanvasOnlyMode))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let first = urls.first {
                viewModel.openImage(url: first)
            }
        }
        .sheet(isPresented: $viewModel.isResizeSheetPresented) {
            ResizeSheetView(viewModel: viewModel)
        }
        .alert("Do you really want to delete this file?", isPresented: $isDeleteConfirmationPresented) {
            Button("CANCEL", role: .cancel) {}
            Button("YES, DELETE", role: .destructive) {
                viewModel.deleteCurrentImage()
            }
        }
        .onAppear {
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewerAdvanceToNextImage)) { _ in
            viewModel.nextImage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewerAdvanceToPreviousImage)) { _ in
            viewModel.previousImage()
        }
        .onChange(of: viewModel.isCanvasOnlyMode) { _, _ in
            viewModel.applyWindowChrome()
        }
        .onChange(of: isSidebarCollapsed) { _, _ in
            guard viewModel.hasCurrentImage, !viewModel.isCropModePresented else { return }
            viewModel.requestFitOnNextLayoutChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            viewModel.applyWindowChrome()
            viewModel.requestFitOnNextLayoutChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            viewModel.isCanvasOnlyMode = false
            viewModel.applyWindowChrome()
            viewModel.requestFitOnNextLayoutChange()
        }
        .alert("Viewer Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue { viewModel.errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var bottomBar: some View {
        let controlsDisabled = viewModel.isCropModePresented || !viewModel.hasCurrentImage

        return HStack(spacing: 8) {
            Button("-") { viewModel.zoomOut() }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(controlsDisabled)

            Text("\(Int(viewModel.currentZoom * 100))%")
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 60)

            Button("+") { viewModel.zoomIn() }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut("=", modifiers: [.command])
                .disabled(controlsDisabled)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text("1%")
                    .font(.system(size: 10))
                    .foregroundStyle(CoffeePalette.textTertiary)

                Slider(
                    value: zoomSliderBinding,
                    in: 0...1,
                    step: 0.001
                )
                .frame(minWidth: 280, maxWidth: 420)
                .disabled(controlsDisabled)

                Text("\(Int(viewModel.currentZoom * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CoffeePalette.textPrimary)
                    .frame(width: 48, alignment: .trailing)
            }

            Spacer(minLength: 12)

            Button("100%") { viewModel.zoomToActual() }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(controlsDisabled)

            Button("Fit") { 
                viewModel.fitToWindow() 
            }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(controlsDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CoffeePalette.backgroundSecondary)
        .overlay(alignment: .top) {
            Rectangle().fill(CoffeePalette.border).frame(height: 1)
        }
    }

    private var zoomSliderBinding: Binding<Double> {
        Binding(
            get: {
                let percent = Double(viewModel.currentZoom * 100)
                return sliderPosition(fromPercent: percent)
            },
            set: { newValue in
                let percent = percent(fromSliderPosition: newValue)
                viewModel.setZoomPercent(percent)
            }
        )
    }

    private var currentSliderPercent: Double {
        percent(fromSliderPosition: zoomSliderBinding.wrappedValue)
    }

    private func sliderPosition(fromPercent percent: Double) -> Double {
        // Support the full zoom range from 1% to 3200%.
        let minPercent = 1.0
        let maxPercent = 3200.0
        let clampedPercent = min(max(percent, minPercent), maxPercent)
        let normalized = (clampedPercent - minPercent) / (maxPercent - minPercent)
        return pow(normalized, 1 / zoomSliderGamma)
    }

    private func percent(fromSliderPosition position: Double) -> Double {
        let clampedPosition = min(max(position, 0), 1)
        let minPercent = 1.0
        let maxPercent = 3200.0
        return minPercent + (maxPercent - minPercent) * pow(clampedPosition, zoomSliderGamma)
    }

    private var cropOverlay: some View {
        CropOverlayView(
            normalizedRect: $viewModel.cropSelectionNormalized,
            imageFrame: viewModel.imageDisplayFrame,
            imagePixelSize: viewModel.currentImagePixelSize,
            onApply: { viewModel.applyCropSelection() },
            onCancel: { viewModel.cancelCropTool() }
        )
    }

    private var checkerboardBackground: some View {
        GeometryReader { geometry in
            let tile: CGFloat = 18
            Canvas { context, _ in
                for row in stride(from: 0, to: geometry.size.height, by: tile) {
                    for col in stride(from: 0, to: geometry.size.width, by: tile) {
                        let isDark = (Int(row / tile) + Int(col / tile)).isMultiple(of: 2)
                        let rect = CGRect(x: col, y: row, width: tile, height: tile)
                        context.fill(Path(rect), with: .color(isDark ? CoffeePalette.backgroundSecondary : CoffeePalette.surfaceElevated))
                    }
                }
            }
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let blockedModifiers = event.modifierFlags.intersection([.command, .option, .control, .function])
            let isFKey = event.keyCode == 3 || (event.charactersIgnoringModifiers?.lowercased() == "f")

            if isFKey,
               blockedModifiers.isEmpty,
               !(NSApp.keyWindow?.firstResponder is NSTextView) {
                viewModel.toggleCanvasFullscreen()
                return nil
            }

            guard event.modifierFlags.contains(.command) else {
                return event
            }

            // Block zoom shortcuts during crop mode
            guard !viewModel.isCropModePresented else {
                return event
            }

            switch event.keyCode {
            case 24, 69:
                viewModel.zoomIn()
                return nil
            case 27, 78:
                viewModel.zoomOut()
                return nil
            case 29:
                if event.modifierFlags.contains(.shift) {
                    viewModel.fitToWindow()
                } else {
                    viewModel.zoomToActual()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private struct CanvasOnlyTopSafeArea: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea(.container, edges: .top)
        } else {
            content
        }
    }
}
