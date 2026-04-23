import ImageCrabConverterCore
import SwiftUI

struct BatchOutputView: View {
    @ObservedObject var viewModel: BatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Format")
                    .frame(width: 60, alignment: .leading)

                Picker("Format", selection: Binding(
                    get: { viewModel.job.output.format },
                    set: { viewModel.job.output.format = $0 }
                )) {
                    ForEach(viewModel.supportedOutputFormats, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Text("Quality")
                    .frame(width: 60, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(viewModel.job.output.quality) },
                        set: { viewModel.job.output.quality = Int($0.rounded()) }
                    ),
                    in: 1...100,
                    step: 1
                )
                .disabled(!viewModel.usesLossyOutputQuality)

                Text("\(viewModel.job.output.quality)%")
                    .frame(width: 40)
                    .foregroundStyle(viewModel.usesLossyOutputQuality ? CoffeePalette.textPrimary : CoffeePalette.textTertiary)
            }

            Picker("Destination", selection: Binding(
                get: { viewModel.outputDestinationMode },
                set: { viewModel.setOutputDestinationMode($0) }
            )) {
                Text("Same Folder").tag(0)
                Text("Custom Folder").tag(1)
            }
            .pickerStyle(.segmented)

            if viewModel.showsCustomOutputFolder {
                HStack(spacing: 8) {
                    TextField("Output folder", text: .constant(viewModel.customOutputFolderPath))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Button("Browse...") {
                        viewModel.chooseOutputFolder()
                    }
                    .buttonStyle(CoffeeButton(prominent: false))
                }
            }

            Toggle("Save to subfolder", isOn: Binding(
                get: { viewModel.isSubfolderEnabled },
                set: { viewModel.setSubfolderEnabled($0) }
            ))

            if viewModel.isSubfolderEnabled {
                HStack(spacing: 8) {
                    Text("Name")
                        .frame(width: 60, alignment: .leading)

                    TextField(
                        "converted",
                        text: Binding(
                            get: { viewModel.outputSubfolderText },
                            set: { viewModel.updateSubfolderName($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
