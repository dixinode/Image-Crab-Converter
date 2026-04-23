import SwiftUI

struct CropOverlayView: View {
    enum Handle: CaseIterable, Identifiable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        var id: String {
            switch self {
            case .topLeft: "topLeft"
            case .top: "top"
            case .topRight: "topRight"
            case .left: "left"
            case .right: "right"
            case .bottomLeft: "bottomLeft"
            case .bottom: "bottom"
            case .bottomRight: "bottomRight"
            }
        }
    }

    /// Normalized rect in IMAGE space (0…1 relative to image pixel dimensions)
    @Binding var normalizedRect: CGRect
    /// Image display frame in canvas coordinates
    let imageFrame: CGRect
    /// Actual image pixel dimensions (for label)
    let imagePixelSize: CGSize
    let onApply: () -> Void
    let onCancel: () -> Void

    @State private var dragStartRect: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let selection = selectionInCanvas()

            ZStack(alignment: .topLeading) {
                dimLayer(in: geometry.size, selection: selection)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .overlay(
                        Rectangle()
                            .stroke(CoffeePalette.accentPrimary, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                    .frame(width: selection.width, height: selection.height)
                    .position(x: selection.midX, y: selection.midY)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartRect == nil { dragStartRect = normalizedRect }
                                guard let start = dragStartRect else { return }
                                normalizedRect = moveRect(start: start, translation: value.translation)
                            }
                            .onEnded { _ in dragStartRect = nil }
                    )

                ForEach(Handle.allCases) { handle in
                    Circle()
                        .fill(CoffeePalette.surfaceElevated)
                        .overlay(Circle().stroke(CoffeePalette.accentPrimary, lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                        .position(position(for: handle, in: selection))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartRect == nil { dragStartRect = normalizedRect }
                                    guard let start = dragStartRect else { return }
                                    normalizedRect = resizeRect(start: start, handle: handle, translation: value.translation)
                                }
                                .onEnded { _ in dragStartRect = nil }
                        )
                }

                Text(label())
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CoffeePalette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .position(x: selection.midX, y: max(18, selection.minY - 16))
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button("Cancel") { onCancel() }
                            .buttonStyle(CoffeeButton(prominent: false))
                        Button("Apply Crop") { onApply() }
                            .buttonStyle(CoffeeButton())
                    }
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Coordinate mapping

    /// Converts normalizedRect (image space 0…1) → canvas pixel rect, clamped to imageFrame
    private func selectionInCanvas() -> CGRect {
        let raw = CGRect(
            x: imageFrame.minX + normalizedRect.minX * imageFrame.width,
            y: imageFrame.minY + normalizedRect.minY * imageFrame.height,
            width: normalizedRect.width * imageFrame.width,
            height: normalizedRect.height * imageFrame.height
        )
        return raw.intersection(imageFrame).isEmpty ? raw : raw.intersection(imageFrame)
    }

    private func label() -> String {
        let pixW = Int((normalizedRect.width * imagePixelSize.width).rounded())
        let pixH = Int((normalizedRect.height * imagePixelSize.height).rounded())
        return "\(pixW) × \(pixH) px"
    }

    private func dimLayer(in size: CGSize, selection: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(width: size.width, height: max(0, selection.minY))

            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(width: size.width, height: max(0, size.height - selection.maxY))
                .offset(x: 0, y: selection.maxY)

            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(width: max(0, selection.minX), height: selection.height)
                .offset(x: 0, y: selection.minY)

            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(width: max(0, size.width - selection.maxX), height: selection.height)
                .offset(x: selection.maxX, y: selection.minY)
        }
        .allowsHitTesting(false)
    }

    private func position(for handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     CGPoint(x: rect.minX, y: rect.minY)
        case .top:         CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:    CGPoint(x: rect.maxX, y: rect.minY)
        case .left:        CGPoint(x: rect.minX, y: rect.midY)
        case .right:       CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:  CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:      CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    // MARK: - Gestures (translation in canvas pixels → image-normalized delta)

    private func moveRect(start: CGRect, translation: CGSize) -> CGRect {
        let dx = translation.width / max(imageFrame.width, 1)
        let dy = translation.height / max(imageFrame.height, 1)
        var rect = start.offsetBy(dx: dx, dy: dy)
        rect.origin.x = min(max(rect.origin.x, 0), 1 - rect.width)
        rect.origin.y = min(max(rect.origin.y, 0), 1 - rect.height)
        return rect
    }

    private func resizeRect(start: CGRect, handle: Handle, translation: CGSize) -> CGRect {
        let dx = translation.width / max(imageFrame.width, 1)
        let dy = translation.height / max(imageFrame.height, 1)
        let minW = max(24 / max(imageFrame.width, 1), 0.02)
        let minH = max(24 / max(imageFrame.height, 1), 0.02)

        var left = start.minX
        var right = start.maxX
        var top = start.minY
        var bottom = start.maxY

        switch handle {
        case .topLeft:     left += dx; top += dy
        case .top:         top += dy
        case .topRight:    right += dx; top += dy
        case .left:        left += dx
        case .right:       right += dx
        case .bottomLeft:  left += dx; bottom += dy
        case .bottom:      bottom += dy
        case .bottomRight: right += dx; bottom += dy
        }

        left   = min(max(left, 0), right - minW)
        right  = max(min(right, 1), left + minW)
        top    = min(max(top, 0), bottom - minH)
        bottom = max(min(bottom, 1), top + minH)

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
