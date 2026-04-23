import SwiftUI
import ImageCrabConverterCore

struct ResizeSheetView: View {
    @ObservedObject var viewModel: ViewerViewModel
    @State private var originalWidth: Int = 0
    @State private var originalHeight: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resize Image")
                .font(.system(size: 15, weight: .semibold))
            
            HStack(alignment: .top, spacing: 20) {
                // Left column for percentage-based sizing.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Percentage")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CoffeePalette.textSecondary)
                    
                    HStack {
                        Text("Width %")
                            .frame(width: 70, alignment: .leading)
                        TextField("Width %", text: Binding(
                            get: { viewModel.resizeWidthPercent },
                            set: { newValue in
                                viewModel.resizeWidthPercent = newValue
                                viewModel.updateResizeWidthPercent()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            viewModel.updateResizeWidthPercent()
                        }
                    }
                    
                    HStack {
                        Text("Height %")
                            .frame(width: 70, alignment: .leading)
                        TextField("Height %", text: Binding(
                            get: { viewModel.resizeHeightPercent },
                            set: { newValue in
                                viewModel.resizeHeightPercent = newValue
                                viewModel.updateResizeHeightPercent()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit {
                            viewModel.updateResizeHeightPercent()
                        }
                    }
                    
                    Text("Original: \(originalWidth) × \(originalHeight) px")
                        .font(.system(size: 11))
                        .foregroundStyle(CoffeePalette.textTertiary)
                        .padding(.top, 4)
                }
                .frame(width: 180)
                
                // Right column for pixel-based sizing.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pixel Dimensions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CoffeePalette.textSecondary)
                    
                    HStack {
                        Text("Width")
                            .frame(width: 70, alignment: .leading)
                        TextField("Width", text: Binding(
                            get: { viewModel.resizeWidth },
                            set: { newValue in
                                viewModel.resizeWidth = newValue
                                viewModel.updateResizeWidthFromPixels()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onSubmit {
                            viewModel.updateResizeWidthFromPixels()
                        }
                        Text("px")
                            .font(.system(size: 11))
                            .foregroundStyle(CoffeePalette.textSecondary)
                    }
                    
                    HStack {
                        Text("Height")
                            .frame(width: 70, alignment: .leading)
                        TextField("Height", text: Binding(
                            get: { viewModel.resizeHeight },
                            set: { newValue in
                                viewModel.resizeHeight = newValue
                                viewModel.updateResizeHeightFromPixels()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .onSubmit {
                            viewModel.updateResizeHeightFromPixels()
                        }
                        Text("px")
                            .font(.system(size: 11))
                            .foregroundStyle(CoffeePalette.textSecondary)
                    }
                    
                    Toggle("Lock aspect ratio", isOn: Binding(
                        get: { viewModel.resizeLockAspect },
                        set: { newValue in
                            viewModel.resizeLockAspect = newValue
                            // Recalculate height from width when aspect ratio lock changes.
                            if newValue {
                                viewModel.updateResizeWidthFromPixels()
                            }
                        }
                    ))
                    .padding(.top, 4)
                }
                .frame(width: 180)
            }
            
            Picker("Resample method", selection: $viewModel.resizeMethod) {
                ForEach(ResampleMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.isResizeSheetPresented = false
                }
                .buttonStyle(CoffeeButton(prominent: false))

                Button("Resize & Save") {
                    viewModel.resizeCurrentImage()
                }
                .buttonStyle(CoffeeButton())
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 420)
        .background(CoffeePalette.backgroundPrimary)
        .onAppear {
            if let document = viewModel.currentDocument {
                originalWidth = document.width
                originalHeight = document.height
            }
        }
    }
}
