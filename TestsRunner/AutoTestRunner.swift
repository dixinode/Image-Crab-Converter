import CoreGraphics
import Foundation
import ImageCrabConverterCore

struct TestFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}

@main
@MainActor
enum AutoTestRunner {
    static func main() async {
        var failures = 0

        await run("FileRenamer tokens", failures: &failures) {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            try TestImageFactory.makePNG(width: 1920, height: 1080, at: temp)
            let file = try ImageDocument(url: temp)

            let renamer = FileRenamer()
            let date = Date(timeIntervalSince1970: 1_744_988_800)
            let output = renamer.applyPattern(
                "{name}_{date}_{time}_{width}x{height}_{n:4}",
                to: file,
                index: 7,
                date: date,
                finalExtension: "jpg"
            )

            try expect(output.contains("_1920x1080_0007"), "Pattern replacement failed")
            try expect(output.hasSuffix(".jpg"), "Final extension is not correct")
        }

        await run("FileRenamer ext token uses final output extension", failures: &failures) {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("capture")
                .appendingPathExtension("png")
            try TestImageFactory.makePNG(width: 1920, height: 1080, at: temp)
            let file = try ImageDocument(url: temp)

            let renamer = FileRenamer()
            let output = renamer.applyPattern(
                "IMG_{n:3}_{date}.{ext}",
                to: file,
                index: 3,
                date: Date(timeIntervalSince1970: 1_744_988_800),
                finalExtension: "jpg"
            )

            try expect(output.hasPrefix("IMG_003_"), "Pattern prefix should still be rendered")
            try expect(output.hasSuffix(".jpg"), "{ext} should match the final output extension")
            try expect(!output.contains(".png.jpg"), "Rename pattern should not produce a double extension")
        }

        await run("FileRenamer rejects unknown tag", failures: &failures) {
            let renamer = FileRenamer()
            let error = renamer.validationError(for: "IMG_{foo}_{date}")

            try expect(error == .unknownToken("foo"), "Unknown rename tag should be reported")
        }

        await run("FileRenamer rejects malformed tag", failures: &failures) {
            let renamer = FileRenamer()
            let error = renamer.validationError(for: "IMG_{n:abc}_{date")

            try expect(error == .invalidNumberPadding("n:abc"), "Malformed number padding should be reported first")
        }

        await run("FileRenamer falls back for empty pattern", failures: &failures) {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("summer_photo")
                .appendingPathExtension("png")
            try TestImageFactory.makePNG(width: 640, height: 480, at: temp)
            let file = try ImageDocument(url: temp)

            let renamer = FileRenamer()
            let output = renamer.applyPattern(
                "   ",
                to: file,
                index: 1,
                date: Date(timeIntervalSince1970: 0),
                finalExtension: "jpg"
            )

            try expect(output == "summer_photo.jpg", "Empty rename pattern should fall back to the original filename")
        }

        await run("FileRenamer falls back for invalid-only pattern", failures: &failures) {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("camera_roll")
                .appendingPathExtension("png")
            try TestImageFactory.makePNG(width: 800, height: 600, at: temp)
            let file = try ImageDocument(url: temp)

            let renamer = FileRenamer()
            let output = renamer.applyPattern(
                "...///___",
                to: file,
                index: 1,
                date: Date(timeIntervalSince1970: 0),
                finalExtension: "png"
            )

            try expect(output == "camera_roll.png", "Invalid-only rename pattern should fall back to the original filename")
        }

        await run("Crop region aspect ratio", failures: &failures) {
            let processor = ImageProcessor()
            let options = CropOptions(enabled: true, mode: .aspectRatio(width: 1, height: 1), anchor: .middleCenter)
            let region = processor.cropRegion(for: CGSize(width: 3000, height: 2000), options: options)

            try expect(Int(region.width.rounded()) == 2000, "Unexpected crop width")
            try expect(Int(region.height.rounded()) == 2000, "Unexpected crop height")
            try expect(Int(region.x.rounded()) == 500, "Unexpected crop x")
        }

        await run("Resize pipeline writes output", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let source = root.appendingPathComponent("input.png")
            let output = root.appendingPathComponent("output.png")
            try TestImageFactory.makePNG(width: 120, height: 80, at: source)

            let doc = try ImageDocument(url: source)
            let job = BatchJob(
                rename: RenameOptions(enabled: false),
                resize: ResizeOptions(enabled: true, width: 60, height: 80, maintainAspectRatio: true, method: .lanczos, resizeOnlyIfLarger: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .png, quality: 85, destination: .sameAsSource, subfolderName: nil)
            )

            let processor = ImageProcessor()
            try processor.processFile(sourceURL: source, sourceFormat: doc.format, job: job, outputURL: output)

            let resized = try ImageDocument(url: output)
            try expect(resized.width == 60, "Resized width mismatch")
            try expect(resized.height == 40, "Resized height mismatch")
        }

        await run("Batch run + rename + subfolder", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let file1 = root.appendingPathComponent("a.png")
            let file2 = root.appendingPathComponent("b.png")
            try TestImageFactory.makePNG(width: 300, height: 200, at: file1)
            try TestImageFactory.makePNG(width: 200, height: 100, at: file2)

            let docs = try [ImageDocument(url: file1), ImageDocument(url: file2)]
            let job = BatchJob(
                rename: RenameOptions(enabled: true, pattern: "photo_{n:3}", startNumber: 1),
                resize: ResizeOptions(enabled: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .png, quality: 85, destination: .sameAsSource, subfolderName: "converted")
            )

            let processor = BatchProcessor(dateProvider: { Date(timeIntervalSince1970: 0) })
            let summary = await processor.runBatch(files: docs, job: job)
            try expect(summary.successCount == 2, "Expected 2 successful files")

            let out1 = root.appendingPathComponent("converted/photo_001.png")
            let out2 = root.appendingPathComponent("converted/photo_002.png")
            try expect(FileManager.default.fileExists(atPath: out1.path), "First output is missing")
            try expect(FileManager.default.fileExists(atPath: out2.path), "Second output is missing")
        }

        await run("Batch custom destination folder", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let outputRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

            let file = root.appendingPathComponent("source.png")
            try TestImageFactory.makePNG(width: 300, height: 200, at: file)

            let doc = try ImageDocument(url: file)
            let job = BatchJob(
                rename: RenameOptions(enabled: true, pattern: "export_{n:2}", startNumber: 1),
                resize: ResizeOptions(enabled: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .png, quality: 85, destination: .custom(outputRoot), subfolderName: "converted")
            )

            let processor = BatchProcessor()
            let summary = await processor.runBatch(files: [doc], job: job)
            try expect(summary.successCount == 1, "Expected batch with custom destination to succeed")

            let output = outputRoot.appendingPathComponent("converted/export_01.png")
            try expect(FileManager.default.fileExists(atPath: output.path), "Custom destination output is missing")
        }

        await run("Batch without subfolder writes directly to destination", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let outputRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

            let file = root.appendingPathComponent("source.png")
            try TestImageFactory.makePNG(width: 240, height: 160, at: file)

            let doc = try ImageDocument(url: file)
            let job = BatchJob(
                rename: RenameOptions(enabled: false),
                resize: ResizeOptions(enabled: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .jpeg, quality: 85, destination: .custom(outputRoot), subfolderName: nil)
            )

            let processor = BatchProcessor()
            let summary = await processor.runBatch(files: [doc], job: job)
            try expect(summary.successCount == 1, "Expected batch without subfolder to succeed")

            let output = outputRoot.appendingPathComponent("source.jpg")
            try expect(FileManager.default.fileExists(atPath: output.path), "Direct destination output is missing")
        }

        await run("Output-only batch writes converted file", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let file = root.appendingPathComponent("source.png")
            try TestImageFactory.makePNG(width: 240, height: 160, at: file)

            let doc = try ImageDocument(url: file)
            let job = BatchJob(
                rename: RenameOptions(enabled: false),
                resize: ResizeOptions(enabled: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .jpeg, quality: 85, destination: .sameAsSource, subfolderName: "converted")
            )

            let processor = BatchProcessor()
            let summary = await processor.runBatch(files: [doc], job: job)
            try expect(summary.successCount == 1, "Expected output-only batch to succeed")
            let output = root.appendingPathComponent("converted/source.jpg")
            try expect(FileManager.default.fileExists(atPath: output.path), "Output-only batch file is missing")
        }

        await run("Batch cancellation", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            var docs: [ImageDocument] = []
            for index in 0..<6 {
                let url = root.appendingPathComponent("img_\(index).png")
                try TestImageFactory.makePNG(width: 2000, height: 1200, at: url)
                docs.append(try ImageDocument(url: url))
            }

            let job = BatchJob(
                rename: RenameOptions(enabled: true, pattern: "exp_{n:3}", startNumber: 1),
                resize: ResizeOptions(enabled: true, width: 1000, height: 500, maintainAspectRatio: true, method: .lanczos, resizeOnlyIfLarger: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .png, quality: 85, destination: .sameAsSource, subfolderName: "cancel_test")
            )

            let processor = BatchProcessor(processingDelayNanoseconds: 150_000_000)
            let task = Task {
                await processor.runBatch(files: docs, job: job)
            }

            try await Task.sleep(nanoseconds: 220_000_000)
            task.cancel()

            let summary = await task.value
            try expect(summary.cancelledCount > 0, "Cancellation should mark at least one file")
        }

        await run("Percent batch resize scales each file independently", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let file1 = root.appendingPathComponent("large.png")
            let file2 = root.appendingPathComponent("small.png")
            try TestImageFactory.makePNG(width: 400, height: 200, at: file1)
            try TestImageFactory.makePNG(width: 200, height: 100, at: file2)

            let docs = try [ImageDocument(url: file1), ImageDocument(url: file2)]
            let job = BatchJob(
                rename: RenameOptions(enabled: false),
                resize: ResizeOptions(enabled: true, width: 200, height: 100, widthPercent: 50, heightPercent: 50, maintainAspectRatio: true, scaleMode: .percent, method: .lanczos, resizeOnlyIfLarger: false),
                crop: CropOptions(enabled: false),
                output: OutputOptions(format: .png, quality: 85, destination: .sameAsSource, subfolderName: "percent_resize")
            )

            let processor = BatchProcessor()
            let summary = await processor.runBatch(files: docs, job: job)
            try expect(summary.successCount == 2, "Expected 2 successful files")

            let out1 = try ImageDocument(url: root.appendingPathComponent("percent_resize/large.png"))
            let out2 = try ImageDocument(url: root.appendingPathComponent("percent_resize/small.png"))
            try expect(out1.width == 200 && out1.height == 100, "First file percent resize mismatch")
            try expect(out2.width == 100 && out2.height == 50, "Second file percent resize mismatch")
        }

        await run("HEIC auto-convert: 45%, upright, dated name", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let heic = root.appendingPathComponent("IMG_0001.HEIC")
            try TestImageFactory.makeHEIC(width: 4000, height: 3000, orientation: 6, dateTimeOriginal: "2026:11:09 10:15:42", at: heic)

            try expect(HEICAutoConverter.isHEIC(heic), "Upper-case .HEIC must be recognised")
            let output = try HEICAutoConverter().convert(sourceURL: heic)

            try expect(output.lastPathComponent == "2026-11-09_10-15-42-auto_converted.jpg", "Unexpected name \(output.lastPathComponent)")
            let doc = try ImageDocument(url: output)
            try expect(doc.format == .jpeg, "Output must be JPEG")
            try expect(doc.width == 1350 && doc.height == 1800, "Expected upright 1350x1800, got \(doc.width)x\(doc.height)")

            let second = try HEICAutoConverter().convert(sourceURL: heic)
            try expect(second.lastPathComponent == "2026-11-09_10-15-42-auto_converted_2.jpg", "Second conversion must not overwrite the first")
        }

        await run("Folder watcher converts only new HEIC files", failures: &failures) {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let suite = "ImageCrabConverterAutoTests.\(UUID().uuidString)"
            let defaults = try unwrap(UserDefaults(suiteName: suite), "defaults")
            defer { defaults.removePersistentDomain(forName: suite) }

            try TestImageFactory.makeHEIC(width: 400, height: 300, at: root.appendingPathComponent("old.heic"))

            let watcher = FolderAutoConverter(directory: root, defaults: defaults, stabilityInterval: 0.3) { _ in }
            watcher.start()
            try await Task.sleep(nanoseconds: 500_000_000)
            try TestImageFactory.makeHEIC(width: 400, height: 300, at: root.appendingPathComponent("new.heic"))

            var jpgs: [String] = []
            for _ in 0..<40 {
                try await Task.sleep(nanoseconds: 100_000_000)
                jpgs = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".jpg") }
                if !jpgs.isEmpty { break }
            }
            try await Task.sleep(nanoseconds: 800_000_000)
            jpgs = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".jpg") }
            watcher.stop()

            try expect(jpgs.count == 1, "Expected exactly one JPEG (for new.heic), got \(jpgs)")
            try expect(jpgs[0].hasSuffix("-auto_converted.jpg"), "Unexpected name \(jpgs[0])")
        }

        if failures > 0 {
            print("\nFAILURES: \(failures)")
            Foundation.exit(1)
        }

        print("\nAll automated tests passed")
    }

    private static func run(
        _ title: String,
        failures: inout Int,
        block: () async throws -> Void
    ) async {
        do {
            try await block()
            print("PASS - \(title)")
        } catch {
            failures += 1
            print("FAIL - \(title): \(error)")
        }
    }

    private static func unwrap<T>(_ value: T?, _ what: String) throws -> T {
        guard let value else { throw TestFailure("Missing \(what)") }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw TestFailure(message)
        }
    }
}
