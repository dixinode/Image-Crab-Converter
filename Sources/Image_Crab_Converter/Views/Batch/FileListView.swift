import ImageCrabConverterCore
import SwiftUI

struct FileListView: View {
    let files: [ImageDocument]
    let statuses: [URL: BatchViewModel.ItemStatus]
    let canRemove: Bool
    let onRemove: (ImageDocument) -> Void

    var body: some View {
        List(files, id: \.url) { file in
            HStack(spacing: 10) {
                statusIcon(for: statuses[file.url] ?? .idle)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(file.width)×\(file.height)  \(file.humanReadableFileSize)")
                        .font(.system(size: 10))
                        .foregroundStyle(CoffeePalette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    onRemove(file)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CoffeePalette.destructive)
                }
                .buttonStyle(.plain)
                .disabled(!canRemove)
            }
            .listRowBackground(CoffeePalette.surfaceElevated)
        }
        .scrollContentBackground(.hidden)
        .background(CoffeePalette.backgroundSecondary)
    }

    private func statusIcon(for status: BatchViewModel.ItemStatus) -> some View {
        Group {
            switch status {
            case .idle:
                Image(systemName: "circle")
            case .processing:
                Image(systemName: "hourglass")
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CoffeePalette.success)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(CoffeePalette.destructive)
            case .cancelled:
                Image(systemName: "slash.circle.fill")
                    .foregroundStyle(CoffeePalette.textTertiary)
            }
        }
        .font(.system(size: 12))
    }
}
