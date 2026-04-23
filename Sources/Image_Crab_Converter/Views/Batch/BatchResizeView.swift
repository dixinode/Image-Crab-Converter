import ImageCrabConverterCore
import SwiftUI

struct BatchResizeView: View {
    @ObservedObject var viewModel: BatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable resize", isOn: Binding(
                get: { viewModel.job.resize.enabled },
                set: { viewModel.job.resize.enabled = $0 }
            ))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("")
                        .frame(width: 18)

                    Text("Percent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CoffeePalette.textSecondary)
                        .frame(width: 86, alignment: .leading)

                    Text("Pixels")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CoffeePalette.textSecondary)
                        .frame(width: 104, alignment: .leading)
                }

                resizeRow(
                    title: "W",
                    percentText: Binding(
                        get: { viewModel.resizeWidthPercentText },
                        set: { newValue in
                            viewModel.resizeWidthPercentText = newValue
                            viewModel.updateResizeWidthPercent()
                        }
                    ),
                    pixelText: Binding(
                        get: { viewModel.resizeWidthText },
                        set: { newValue in
                            viewModel.resizeWidthText = newValue
                            viewModel.updateResizeWidthFromPixels()
                        }
                    ),
                    percentPlaceholder: "%",
                    pixelPlaceholder: "px",
                    pixelDisabled: false
                )

                resizeRow(
                    title: "H",
                    percentText: Binding(
                        get: { viewModel.resizeHeightPercentText },
                        set: { newValue in
                            viewModel.resizeHeightPercentText = newValue
                            viewModel.updateResizeHeightPercent()
                        }
                    ),
                    pixelText: Binding(
                        get: { viewModel.resizeHeightText },
                        set: { newValue in
                            viewModel.resizeHeightText = newValue
                            viewModel.updateResizeHeightFromPixels()
                        }
                    ),
                    percentPlaceholder: "%",
                    pixelPlaceholder: "px",
                    pixelDisabled: viewModel.job.resize.maintainAspectRatio,
                    percentDisabled: viewModel.job.resize.maintainAspectRatio
                )
            }

            Toggle("Lock aspect ratio", isOn: Binding(
                get: { viewModel.job.resize.maintainAspectRatio },
                set: { viewModel.setResizeAspectLock($0) }
            ))

            if !viewModel.referenceResizeLabel.isEmpty {
                Text(viewModel.referenceResizeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(CoffeePalette.textTertiary)
            }

            if !viewModel.resizePercentagesHint.isEmpty {
                Text(viewModel.resizePercentagesHint)
                    .font(.system(size: 10))
                    .foregroundStyle(CoffeePalette.textSecondary)
            }

            HStack(spacing: 8) {
                Text("Method")
                    .frame(width: 52, alignment: .leading)

                Picker("Method", selection: Binding(
                    get: { viewModel.job.resize.method },
                    set: { viewModel.job.resize.method = $0 }
                )) {
                    ForEach(ResampleMethod.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .labelsHidden()
            }

            Toggle("Resize only if larger", isOn: Binding(
                get: { viewModel.job.resize.resizeOnlyIfLarger },
                set: { viewModel.job.resize.resizeOnlyIfLarger = $0 }
            ))
        }
        .onAppear {
            viewModel.syncResizeInputsFromJob()
        }
    }

    private func resizeRow(
        title: String,
        percentText: Binding<String>,
        pixelText: Binding<String>,
        percentPlaceholder: String,
        pixelPlaceholder: String,
        pixelDisabled: Bool,
        percentDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CoffeePalette.textSecondary)
                .frame(width: 18, alignment: .leading)

            TextField(percentPlaceholder, text: percentText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
                .disabled(percentDisabled)

            TextField(pixelPlaceholder, text: pixelText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 104)
                .disabled(pixelDisabled)
        }
    }
}
