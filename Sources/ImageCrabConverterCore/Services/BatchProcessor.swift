import Foundation

public actor BatchProcessor {
    private let imageProcessor: ImageProcessor
    private let renamer: FileRenamer
    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date
    private let processingDelayNanoseconds: UInt64

    public init(
        imageProcessor: ImageProcessor = .init(),
        renamer: FileRenamer = .init(),
        fileManager: FileManager = .default,
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        processingDelayNanoseconds: UInt64 = 0
    ) {
        self.imageProcessor = imageProcessor
        self.renamer = renamer
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.processingDelayNanoseconds = processingDelayNanoseconds
    }

    public func runBatch(
        files: [ImageDocument],
        job: BatchJob,
        onProgress: (@Sendable (BatchProgress) async -> Void)? = nil
    ) async -> BatchRunSummary {
        guard !files.isEmpty else {
            return BatchRunSummary(results: [])
        }

        var results: [BatchFileResult] = []

        for (offset, file) in files.enumerated() {
            if Task.isCancelled {
                results.append(BatchFileResult(file: file.url, outputURL: nil, status: .cancelled))
                continue
            }

            await onProgress?(BatchProgress(currentIndex: offset + 1, totalCount: files.count, filename: file.name))

            do {
                try Task.checkCancellation()

                if processingDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: processingDelayNanoseconds)
                    try Task.checkCancellation()
                }

                let outputURL = try prepareOutputURL(for: file, index: offset, job: job)
                try imageProcessor.processFile(
                    sourceURL: file.url,
                    sourceFormat: file.format,
                    job: job,
                    outputURL: outputURL
                )

                results.append(BatchFileResult(file: file.url, outputURL: outputURL, status: .success))
            } catch is CancellationError {
                results.append(BatchFileResult(file: file.url, outputURL: nil, status: .cancelled))
            } catch {
                results.append(BatchFileResult(file: file.url, outputURL: nil, status: .failure(error.localizedDescription)))
            }
        }

        return BatchRunSummary(results: results)
    }

    public func previewNames(
        files: [ImageDocument],
        job: BatchJob,
        limit: Int = 3
    ) -> [String] {
        let finalExtension = outputExtension(for: job, fallback: "jpg")
        if job.rename.enabled {
            return renamer.preview(
                pattern: job.rename.pattern,
                files: files,
                startNumber: job.rename.startNumber,
                date: dateProvider(),
                finalExtension: finalExtension,
                limit: limit
            )
        }

        return files.prefix(limit).map { "\($0.nameWithoutExtension).\(finalExtension)" }
    }

    private func prepareOutputURL(for file: ImageDocument, index: Int, job: BatchJob) throws -> URL {
        let targetDirectory: URL = {
            switch job.output.destination {
            case .sameAsSource:
                file.url.deletingLastPathComponent()
            case let .custom(url):
                url
            }
        }()

        let directoryWithSubfolder: URL = {
            guard let subfolder = job.output.subfolderName?.trimmingCharacters(in: .whitespacesAndNewlines), !subfolder.isEmpty else {
                return targetDirectory
            }
            return targetDirectory.appendingPathComponent(subfolder, isDirectory: true)
        }()

        try fileManager.createDirectory(at: directoryWithSubfolder, withIntermediateDirectories: true)

        let finalExtension = outputExtension(for: job, fallback: file.fileExtension)
        let filename: String
        if job.rename.enabled {
            filename = renamer.applyPattern(
                job.rename.pattern,
                to: file,
                index: job.rename.startNumber + index,
                date: dateProvider(),
                finalExtension: finalExtension
            )
        } else {
            filename = "\(file.nameWithoutExtension).\(finalExtension)"
        }

        let candidate = directoryWithSubfolder.appendingPathComponent(filename)
        return uniqueURLIfNeeded(candidate)
    }

    private func outputExtension(for job: BatchJob, fallback: String) -> String {
        switch job.output.format {
        case .sameAsSource:
            if fallback.isEmpty {
                return "png"
            }
            return fallback
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

    private func uniqueURLIfNeeded(_ url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let directory = url.deletingLastPathComponent()

        var counter = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base)_\(counter)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
