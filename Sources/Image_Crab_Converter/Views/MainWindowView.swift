import AppKit
import SwiftUI

enum AppMode: String, CaseIterable, Identifiable {
    case viewer = "Viewer"
    case batch = "Batch"

    var id: String { rawValue }
}

struct MainWindowView: View {
    private let batchTopInset: CGFloat = 12

    @State private var selectedMode: AppMode = .viewer
    @AppStorage("app.sidebarCollapsed") private var isSidebarCollapsed = false
    @ObservedObject var viewerViewModel: ViewerViewModel
    @ObservedObject var batchViewModel: BatchViewModel

    var body: some View {
        Group {
            if selectedMode == .viewer, viewerViewModel.isCanvasOnlyMode {
                ViewerView(viewModel: viewerViewModel, isSidebarCollapsed: $isSidebarCollapsed)
                    .background(Color.black)
            } else {
                VStack(spacing: 0) {
                    if selectedMode == .batch {
                        Rectangle()
                            .fill(CoffeePalette.backgroundPrimary)
                            .frame(height: batchTopInset)
                    }

                    HStack(spacing: 0) {
                        if !isSidebarCollapsed {
                            SidebarView(
                                selectedMode: $selectedMode,
                                viewerDocument: selectedMode == .viewer ? viewerViewModel.currentDocument : nil
                            )
                            .frame(width: 220)
                        }

                        Group {
                            switch selectedMode {
                            case .viewer:
                                ViewerView(viewModel: viewerViewModel, isSidebarCollapsed: $isSidebarCollapsed)
                            case .batch:
                                BatchView(viewModel: batchViewModel)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CoffeePalette.backgroundPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            applyWindowConfiguration(for: selectedMode)
        }
        .onChange(of: selectedMode) { _, newMode in
            applyWindowConfiguration(for: newMode)
        }
    }

    private func applyWindowConfiguration(for mode: AppMode) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        switch mode {
        case .viewer:
            window.contentMinSize = CGSize(width: 1080, height: 700)
            viewerViewModel.applyWindowChrome()
        case .batch:
            let minimumSize = CGSize(width: 1260, height: 760)
            window.contentMinSize = minimumSize
            window.title = "Image_Crab_Converter"
            window.representedURL = nil
            window.titleVisibility = .hidden
            window.toolbar?.isVisible = false
            window.backgroundColor = .windowBackgroundColor

            if window.frame.width < minimumSize.width || window.frame.height < minimumSize.height {
                window.setContentSize(
                    CGSize(
                        width: max(window.contentLayoutRect.width, minimumSize.width),
                        height: max(window.contentLayoutRect.height, minimumSize.height)
                    )
                )
            }
        }
    }
}
