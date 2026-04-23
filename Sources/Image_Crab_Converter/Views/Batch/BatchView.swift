import Foundation
import ImageCrabConverterCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BatchView: View {
    @ObservedObject var viewModel: BatchViewModel
    @State private var isImporting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftPane
            rightPane
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(CoffeePalette.backgroundPrimary)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard !viewModel.isRunning else { return }
            if case let .success(urls) = result {
                viewModel.addFiles(urls: urls)
            }
        }
        .onChange(of: viewModel.job) { _, _ in
            viewModel.updatePreview()
        }
    }

    private var leftPane: some View {
        VStack(spacing: 10) {
            if viewModel.files.isEmpty {
                DropZoneView {
                    isImporting = true
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
            } else {
                FileListView(files: viewModel.files, statuses: viewModel.statuses, canRemove: !viewModel.isRunning) {
                    viewModel.removeFile($0)
                }
                .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
            }

            HStack {
                Button("Clear All") {
                    viewModel.clearAll()
                }
                .buttonStyle(CoffeeButton(prominent: false))
                .disabled(viewModel.isRunning)

                Spacer()

                Text("\(viewModel.files.count) files")
                    .font(.system(size: 11))
                    .foregroundStyle(CoffeePalette.textSecondary)
            }
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .layoutPriority(1)
    }

    private var rightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sectionCard(title: "RENAME") {
                    RenamePatternView(
                        enabled: binding(
                            get: { viewModel.job.rename.enabled },
                            set: { viewModel.job.rename.enabled = $0 }
                        ),
                        pattern: binding(
                            get: { viewModel.job.rename.pattern },
                            set: { viewModel.job.rename.pattern = $0 }
                        ),
                        startNumber: binding(
                            get: { viewModel.job.rename.startNumber },
                            set: { viewModel.job.rename.startNumber = $0 }
                    ),
                    preview: viewModel.previewNames,
                    notice: viewModel.renamePatternNotice,
                    error: viewModel.renamePatternError
                )
            }
                .disabled(viewModel.isRunning)

                sectionCard(title: "RESIZE") {
                    BatchResizeView(viewModel: viewModel)
                }
                .disabled(viewModel.isRunning)

                sectionCard(title: "CROP") {
                    BatchCropView(
                        enabled: binding(get: { viewModel.job.crop.enabled }, set: { viewModel.job.crop.enabled = $0 }),
                        mode: binding(get: { viewModel.job.crop.mode }, set: { viewModel.job.crop.mode = $0 }),
                        anchor: binding(get: { viewModel.job.crop.anchor }, set: { viewModel.job.crop.anchor = $0 })
                    )
                }
                .disabled(viewModel.isRunning)

            sectionCard(title: "OUTPUT") {
                BatchOutputView(viewModel: viewModel)
            }
            .disabled(viewModel.isRunning)

                if let progress = viewModel.progress, viewModel.isRunning {
                    BatchProgressView(
                        current: progress.currentIndex,
                        total: progress.totalCount,
                        currentFile: progress.filename,
                        cancelAction: viewModel.cancelBatch
                    )
                } else {
                    Button("▶  Run Batch  (\(viewModel.files.count) files)") {
                        viewModel.runBatch()
                    }
                    .buttonStyle(CoffeeButton())
                    .disabled(!viewModel.canRunBatch)
                }

                if !viewModel.summaryLabel.isEmpty {
                    Text(viewModel.summaryLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CoffeePalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
            .controlSize(.small)
        }
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 460, maxHeight: .infinity, alignment: .top)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title)
            content()
        }
        .padding(10)
        .background(CoffeePalette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CoffeePalette.border, lineWidth: 1)
        )
    }

    private func binding<T>(
        get: @escaping @MainActor @Sendable () -> T,
        set: @escaping @MainActor @Sendable (T) -> Void
    ) -> Binding<T> {
        Binding(get: { get() }, set: { set($0) })
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !viewModel.isRunning else { return false }
        let identifier = UTType.fileURL.identifier
        for provider in providers where provider.hasItemConformingToTypeIdentifier(identifier) {
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                let droppedURL: URL? = {
                    if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    if let url = item as? URL {
                        return url
                    }
                    return nil
                }()

                guard let droppedURL else { return }
                Task { @MainActor in
                    viewModel.addFiles(urls: [droppedURL])
                }
            }
        }
        return !providers.isEmpty
    }
}
