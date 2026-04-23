import SwiftUI
import UniformTypeIdentifiers

@main
struct ImageCrabConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewerViewModel = ViewerViewModel()
    @StateObject private var batchViewModel = BatchViewModel()

    var body: some Scene {
        WindowGroup("Image_Crab_Converter") {
            MainWindowView(viewerViewModel: viewerViewModel, batchViewModel: batchViewModel)
                .frame(minWidth: 1080, minHeight: 700)
                .onOpenURL { url in
                    viewerViewModel.openImage(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image, .pdf]
                    panel.allowsMultipleSelection = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    viewerViewModel.openImage(url: url)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandGroup(replacing: .windowSize) {
                Button("Zoom In") {
                    viewerViewModel.zoomIn()
                }
                .keyboardShortcut("=", modifiers: [.command])

                Button("Zoom Out") {
                    viewerViewModel.zoomOut()
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Actual Size (100%)") {
                    viewerViewModel.zoomToActual()
                }
                .keyboardShortcut("0", modifiers: [.command])

                Button("Fit to Window") {
                    viewerViewModel.fitToWindow()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }

            CommandMenu("Image") {
                Button("Crop...") {
                    viewerViewModel.openCropTool()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Resize...") {
                    viewerViewModel.isResizeSheetPresented = true
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

        }

        Settings {
            Form {
                Text("Image_Crab_Converter")
                    .font(.title3.weight(.semibold))
                Text("v1.0 coffee theme preferences")
                    .foregroundStyle(CoffeePalette.textSecondary)
            }
            .padding(20)
            .frame(width: 420)
            .background(CoffeePalette.backgroundPrimary)
        }
    }
}
