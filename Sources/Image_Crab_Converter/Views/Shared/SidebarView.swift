import SwiftUI
import ImageCrabConverterCore

struct SidebarView: View {
    @Binding var selectedMode: AppMode
    let viewerDocument: ImageDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Image_Crab_Converter")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CoffeePalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Picker("Mode", selection: $selectedMode) {
                ForEach(AppMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if selectedMode == .viewer {
                Divider()

                Text("FILE INFO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CoffeePalette.textSecondary)

                metadataRow(label: "Name", value: viewerDocument?.name ?? "-")
                metadataRow(label: "Dimensions", value: viewerDocument?.dimensionsLabel ?? "-")
                metadataRow(label: "Size", value: viewerDocument?.humanReadableFileSize ?? "-")
                metadataRow(label: "Format", value: viewerDocument?.format.rawValue.uppercased() ?? "-")
                metadataRow(label: "Color", value: viewerDocument?.colorSpace ?? "-")
            }

            Spacer()

            Text("Warm minimal image toolkit")
                .font(.system(size: 11))
                .foregroundStyle(CoffeePalette.textSecondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CoffeePalette.backgroundTertiary)
        .overlay(
            Rectangle()
                .fill(CoffeePalette.border)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CoffeePalette.textTertiary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(CoffeePalette.textPrimary)
                .lineLimit(2)
        }
    }
}
