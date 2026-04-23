import SwiftUI

struct ViewerToolbarView: View {
    @ObservedObject var viewModel: ViewerViewModel
    @Binding var isSidebarCollapsed: Bool
    @Binding var useCheckerboardCanvas: Bool
    let openAction: () -> Void
    let deleteAction: () -> Void

    private var hasImage: Bool {
        viewModel.hasCurrentImage
    }

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Button {
                    isSidebarCollapsed.toggle()
                } label: {
                    Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.right")
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .help(isSidebarCollapsed ? "Show side panel" : "Hide side panel")

                Divider()
                    .frame(height: 16)

                Button("Open", action: openAction)
                    .buttonStyle(CoffeeButton())
                    .keyboardShortcut("o", modifiers: [.command])

                Button("BG") {
                    useCheckerboardCanvas.toggle()
                }
                .buttonStyle(CoffeeButton(prominent: !useCheckerboardCanvas))
                .help(useCheckerboardCanvas ? "Switch canvas to black" : "Switch canvas to checkerboard")
                .disabled(!hasImage)

                Button("F") {
                    viewModel.toggleCanvasFullscreen()
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .help("Toggle canvas full screen")
                .disabled(!hasImage)

                Button("Crop") {
                    viewModel.openCropTool()
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(!hasImage)

                Button("Resize") {
                    viewModel.isResizeSheetPresented = true
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!hasImage)

                Button("Delete", action: deleteAction)
                    .buttonStyle(CoffeeButton(prominent: false))
                    .disabled(!hasImage)

                Spacer()

                Text("Viewer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CoffeePalette.textSecondary)
            }

            HStack(spacing: 10) {
                Button(action: viewModel.previousImage) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!hasImage)

                Button(action: viewModel.nextImage) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!hasImage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(CoffeePalette.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CoffeePalette.border).frame(height: 1)
        }
    }
}
