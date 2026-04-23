import AppKit
import Foundation
import ImageCrabConverterCore

@MainActor
final class BatchViewModel: ObservableObject {
    enum ItemStatus {
        case idle
        case processing
        case success
        case failure
        case cancelled
    }

    @Published var files: [ImageDocument] = []
    @Published var job = BatchJob(
        rename: RenameOptions(enabled: false, pattern: "IMG_{n:3}_{date}.{ext}", startNumber: 1),
        resize: ResizeOptions(enabled: false, width: 1920, height: 1080, widthPercent: 100, heightPercent: 100, maintainAspectRatio: true, scaleMode: .percent, method: .lanczos, resizeOnlyIfLarger: false),
        crop: CropOptions(enabled: false, mode: .fixedSize(width: 800, height: 600), anchor: .middleCenter),
        output: OutputOptions(format: .sameAsSource, quality: 85, destination: .sameAsSource, subfolderName: "converted")
    )

    @Published var previewNames: [String] = []
    @Published var progress: BatchProgress?
    @Published var isRunning = false
    @Published var summaryLabel = ""
    @Published var statuses: [URL: ItemStatus] = [:]
    @Published var resizeWidthText = "1920"
    @Published var resizeHeightText = "1080"
    @Published var resizeWidthPercentText = "100"
    @Published var resizeHeightPercentText = "100"
    @Published var isOutputSubfolderEnabled = true
    @Published var outputSubfolderText = "converted"

    private let processor = BatchProcessor()
    private let imageProcessor = ImageProcessor()
    private let renamer = FileRenamer()
    private var runTask: Task<Void, Never>?

    var supportedOutputFormats: [OutputFormat] {
        [.sameAsSource] + ImageProcessor.supportedExplicitOutputFormats()
    }

    var referenceResizeLabel: String {
        guard let reference = referenceDocument else { return "" }
        return "Reference: \(reference.width) × \(reference.height) px"
    }

    var resizePercentagesHint: String {
        if files.count > 1 {
            return "Percentages are applied to each file individually. Pixel preview is based on the first selected image."
        }
        return ""
    }

    private var referenceDocument: ImageDocument? {
        files.first
    }

    var canRunBatch: Bool {
        !files.isEmpty && !isRunning && renamePatternError == nil
    }

    var renamePatternNotice: String? {
        guard job.rename.enabled else { return nil }

        if job.rename.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Empty pattern falls back to the original filename."
        }

        return nil
    }

    var renamePatternError: String? {
        guard job.rename.enabled else { return nil }
        return renamer.validationError(for: job.rename.pattern)?.message
    }

    var outputDestinationMode: Int {
        switch job.output.destination {
        case .sameAsSource:
            return 0
        case .custom:
            return 1
        }
    }

    var customOutputFolderPath: String {
        guard case let .custom(url) = job.output.destination else {
            return ""
        }
        return url.path
    }

    var showsCustomOutputFolder: Bool {
        outputDestinationMode == 1
    }

    var usesLossyOutputQuality: Bool {
        job.output.format == .jpeg || job.output.format == .webp
    }

    var isSubfolderEnabled: Bool {
        isOutputSubfolderEnabled
    }

    func addFiles(urls: [URL]) {
        let existing = Set(files.map(\.url))
        let filtered = urls.filter { !existing.contains($0) }

        let loaded = filtered.compactMap { url -> ImageDocument? in
            try? ImageDocument(url: url)
        }

        files.append(contentsOf: loaded)
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        statuses = Dictionary(uniqueKeysWithValues: files.map { ($0.url, .idle) })
        syncResizeInputsFromJob()
        updatePreview()
    }

    func removeFile(_ file: ImageDocument) {
        files.removeAll { $0.url == file.url }
        statuses[file.url] = nil
        syncResizeInputsFromJob()
        updatePreview()
    }

    func clearAll() {
        runTask?.cancel()
        runTask = nil
        files.removeAll()
        previewNames.removeAll()
        statuses.removeAll()
        progress = nil
        isRunning = false
        summaryLabel = ""
        syncResizeInputsFromJob()
    }

    func setSubfolderEnabled(_ isEnabled: Bool) {
        isOutputSubfolderEnabled = isEnabled

        if isEnabled {
            let trimmed = outputSubfolderText.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = trimmed.isEmpty ? "converted" : trimmed
            outputSubfolderText = resolved
            job.output.subfolderName = resolved
        } else {
            if let current = job.output.subfolderName?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty {
                outputSubfolderText = current
            }
            job.output.subfolderName = nil
        }
    }

    func updateSubfolderName(_ newValue: String) {
        outputSubfolderText = newValue
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        job.output.subfolderName = trimmed.isEmpty ? nil : trimmed
    }

    func setOutputDestinationMode(_ mode: Int) {
        if mode == 0 {
            job.output.destination = .sameAsSource
            return
        }

        if case .custom = job.output.destination {
            return
        }

        chooseOutputFolder()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.message = "Select the folder where converted files should be saved."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if case let .custom(url) = job.output.destination {
            panel.directoryURL = url
        } else if let referenceDocument {
            panel.directoryURL = referenceDocument.url.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        job.output.destination = .custom(url)
    }

    func updatePreview() {
        guard !files.isEmpty else {
            previewNames = []
            return
        }

        guard renamePatternError == nil else {
            previewNames = []
            return
        }

        let ext = outputExtension(for: job)
        if job.rename.enabled {
            previewNames = renamer.preview(
                pattern: job.rename.pattern,
                files: files,
                startNumber: job.rename.startNumber,
                date: Date(),
                finalExtension: ext,
                limit: 3
            )
        } else {
            previewNames = files.prefix(3).map { "\($0.nameWithoutExtension).\(ext)" }
        }
    }

    func runBatch() {
        if let renamePatternError {
            summaryLabel = renamePatternError
            return
        }

        guard canRunBatch else { return }

        let filesToProcess = files
        let jobToRun = job

        isRunning = true
        summaryLabel = ""
        statuses = Dictionary(uniqueKeysWithValues: filesToProcess.map { ($0.url, .idle) })

        runTask = Task { [weak self] in
            guard let self else { return }

            let summary = await processor.runBatch(files: filesToProcess, job: jobToRun) { [weak self] update in
                await MainActor.run {
                    guard let self else { return }
                    self.progress = update
                    let current = filesToProcess[update.currentIndex - 1]
                    self.statuses[current.url] = .processing
                }
            }

            await MainActor.run {
                self.isRunning = false
                self.progress = nil
                self.runTask = nil

                for result in summary.results {
                    switch result.status {
                    case .success:
                        self.statuses[result.file] = .success
                    case .failure:
                        self.statuses[result.file] = .failure
                    case .cancelled:
                        self.statuses[result.file] = .cancelled
                    case .skipped:
                        self.statuses[result.file] = .idle
                    }
                }

                if summary.cancelledCount > 0 {
                    if summary.failureCount > 0 {
                        self.summaryLabel = "Batch cancelled (\(summary.successCount) done, \(summary.failureCount) error, \(summary.cancelledCount) cancelled)"
                    } else {
                        self.summaryLabel = "Batch cancelled (\(summary.successCount) done, \(summary.cancelledCount) cancelled)"
                    }
                } else if summary.failureCount == 0 {
                    self.summaryLabel = "\(summary.successCount) files processed successfully"
                } else {
                    self.summaryLabel = "\(summary.successCount) done, \(summary.failureCount) error"
                }
            }
        }
    }

    func cancelBatch() {
        runTask?.cancel()
        summaryLabel = "Cancelling batch..."
    }

    func syncResizeInputsFromJob() {
        let referenceWidth = max(referenceDocument?.width ?? job.resize.width, 1)
        let referenceHeight = max(referenceDocument?.height ?? job.resize.height, 1)
        let widthPercent = max(job.resize.widthPercent, 1)
        let heightPercent = max(job.resize.heightPercent, 1)
        let width = max(1, Int((Double(referenceWidth) * Double(widthPercent) / 100).rounded()))
        let height: Int
        if job.resize.maintainAspectRatio {
            height = max(1, Int((Double(referenceHeight) * Double(widthPercent) / 100).rounded()))
        } else {
            height = max(1, Int((Double(referenceHeight) * Double(heightPercent) / 100).rounded()))
        }

        resizeWidthText = String(width)
        resizeHeightText = String(height)
        resizeWidthPercentText = String(widthPercent)
        resizeHeightPercentText = String(job.resize.maintainAspectRatio ? widthPercent : heightPercent)
        job.resize.width = width
        job.resize.height = height
        job.resize.scaleMode = .percent
    }

    func updateResizeWidthFromPixels() {
        let referenceWidth = max(referenceDocument?.width ?? job.resize.width, 1)
        let referenceHeight = max(referenceDocument?.height ?? job.resize.height, 1)
        let widthDigits = resizeWidthText.filter { $0.isNumber }
        guard !widthDigits.isEmpty else { return }

        let widthValue = Int(widthDigits) ?? job.resize.width
        let clampedWidth = max(1, widthValue)

        resizeWidthText = String(clampedWidth)
        job.resize.width = clampedWidth
        let widthPercent = max(1, Int((Double(clampedWidth) / Double(referenceWidth) * 100).rounded()))
        resizeWidthPercentText = String(widthPercent)
        job.resize.widthPercent = widthPercent
        job.resize.scaleMode = .percent

        if job.resize.maintainAspectRatio {
            let aspectRatio = Double(referenceHeight) / Double(referenceWidth)
            let calculatedHeight = max(1, Int((Double(clampedWidth) * aspectRatio).rounded()))
            resizeHeightText = String(calculatedHeight)
            resizeHeightPercentText = String(widthPercent)
            job.resize.height = calculatedHeight
            job.resize.heightPercent = widthPercent
        }
    }

    func updateResizeHeightFromPixels() {
        let referenceWidth = max(referenceDocument?.width ?? job.resize.width, 1)
        let referenceHeight = max(referenceDocument?.height ?? job.resize.height, 1)
        let heightDigits = resizeHeightText.filter { $0.isNumber }
        guard !heightDigits.isEmpty else { return }

        let heightValue = Int(heightDigits) ?? job.resize.height
        let clampedHeight = max(1, heightValue)

        resizeHeightText = String(clampedHeight)
        job.resize.height = clampedHeight
        let heightPercent = max(1, Int((Double(clampedHeight) / Double(referenceHeight) * 100).rounded()))
        resizeHeightPercentText = String(heightPercent)
        job.resize.heightPercent = heightPercent
        job.resize.scaleMode = .percent

        if job.resize.maintainAspectRatio {
            let aspectRatio = Double(referenceWidth) / Double(referenceHeight)
            let calculatedWidth = max(1, Int((Double(clampedHeight) * aspectRatio).rounded()))
            resizeWidthText = String(calculatedWidth)
            resizeWidthPercentText = String(heightPercent)
            job.resize.width = calculatedWidth
            job.resize.widthPercent = heightPercent
        }
    }

    func updateResizeWidthPercent() {
        let referenceWidth = max(referenceDocument?.width ?? job.resize.width, 1)
        let referenceHeight = max(referenceDocument?.height ?? job.resize.height, 1)
        let widthPercentDigits = resizeWidthPercentText.replacingOccurrences(of: "%", with: "").filter { $0.isNumber }
        guard !widthPercentDigits.isEmpty else { return }

        let widthPercent = Int(widthPercentDigits) ?? 100
        let clampedPercent = min(max(widthPercent, 1), 10_000)

        resizeWidthPercentText = String(clampedPercent)
        let calculatedWidth = max(1, Int((Double(referenceWidth) * Double(clampedPercent) / 100).rounded()))
        resizeWidthText = String(calculatedWidth)
        job.resize.width = calculatedWidth
        job.resize.widthPercent = clampedPercent
        job.resize.scaleMode = .percent

        if job.resize.maintainAspectRatio {
            let calculatedHeight = max(1, Int((Double(referenceHeight) * Double(clampedPercent) / 100).rounded()))
            resizeHeightPercentText = String(clampedPercent)
            resizeHeightText = String(calculatedHeight)
            job.resize.height = calculatedHeight
            job.resize.heightPercent = clampedPercent
        }
    }

    func updateResizeHeightPercent() {
        let referenceWidth = max(referenceDocument?.width ?? job.resize.width, 1)
        let referenceHeight = max(referenceDocument?.height ?? job.resize.height, 1)
        let heightPercentDigits = resizeHeightPercentText.replacingOccurrences(of: "%", with: "").filter { $0.isNumber }
        guard !heightPercentDigits.isEmpty else { return }

        let heightPercent = Int(heightPercentDigits) ?? 100
        let clampedPercent = min(max(heightPercent, 1), 10_000)

        resizeHeightPercentText = String(clampedPercent)
        let calculatedHeight = max(1, Int((Double(referenceHeight) * Double(clampedPercent) / 100).rounded()))
        resizeHeightText = String(calculatedHeight)
        job.resize.height = calculatedHeight
        job.resize.heightPercent = clampedPercent
        job.resize.scaleMode = .percent

        if job.resize.maintainAspectRatio {
            let calculatedWidth = max(1, Int((Double(referenceWidth) * Double(clampedPercent) / 100).rounded()))
            resizeWidthPercentText = String(clampedPercent)
            resizeWidthText = String(calculatedWidth)
            job.resize.width = calculatedWidth
            job.resize.widthPercent = clampedPercent
        }
    }

    func setResizeAspectLock(_ isEnabled: Bool) {
        job.resize.maintainAspectRatio = isEnabled
        if isEnabled {
            job.resize.heightPercent = job.resize.widthPercent
            updateResizeWidthFromPixels()
        }
    }

    private func outputExtension(for job: BatchJob) -> String {
        switch job.output.format {
        case .sameAsSource:
            if let file = files.first {
                if let resolved = try? imageProcessor.resolveOutputType(
                    output: .sameAsSource,
                    sourceFormat: file.format,
                    explicitExtension: file.fileExtension
                ) {
                    return resolved.fileExtension
                }
            }

            if let ext = files.first?.fileExtension, !ext.isEmpty {
                return ext
            }
            return "png"
        case .jpeg:
            return "jpg"
        case .png:
            return "png"
        case .tiff:
            return "tiff"
        case .webp:
            return "webp"
        }
    }
}
