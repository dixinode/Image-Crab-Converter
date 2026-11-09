import Foundation

/// Watches one folder (non-recursively) and converts every new HEIC that lands in it.
///
/// - Files already in the folder the very first time the watcher runs are left alone
///   (we don't want to convert years of old Downloads).
/// - Files added while the app was not running are picked up on the next start.
/// - A file is converted only after its size and modification date stop changing,
///   so AirDrop / browser downloads that are still being written are not touched.
public final class FolderAutoConverter: @unchecked Sendable {
    public enum Event: Sendable {
        case converted(source: URL, output: URL)
        case failed(source: URL, message: String)
    }

    public let directory: URL

    private let converter: HEICAutoConverter
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let stabilityInterval: TimeInterval
    private let onEvent: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "ImageCrabConverter.FolderAutoConverter")

    // All state below is touched only on `queue`.
    private var source: DispatchSourceFileSystemObject?
    private var pendingRescan: DispatchWorkItem?
    private var processed: Set<String> = []
    private var candidates: [String: (fingerprint: String, firstSeen: Date)] = [:]
    private var failures: [String: Int] = [:]
    private let maxAttempts = 5

    private var processedKey: String { "autoConvert.processed.\(directory.path)" }
    private var baselineKey: String { "autoConvert.baselineDone.\(directory.path)" }

    public init(
        directory: URL,
        converter: HEICAutoConverter = .init(),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        stabilityInterval: TimeInterval = 1.5,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.directory = directory.standardizedFileURL
        self.converter = converter
        self.fileManager = fileManager
        self.defaults = defaults
        self.stabilityInterval = stabilityInterval
        self.onEvent = onEvent
    }

    deinit {
        source?.cancel()
    }

    public func start() {
        queue.async { [self] in
            guard source == nil else { return }

            processed = Set(defaults.stringArray(forKey: processedKey) ?? [])
            if !defaults.bool(forKey: baselineKey) {
                for url in heicFiles() {
                    if let fingerprint = fingerprint(of: url) {
                        processed.insert(fingerprint)
                    }
                }
                defaults.set(true, forKey: baselineKey)
                saveProcessed()
            }

            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else {
                onEvent(.failed(source: directory, message: "Cannot watch \(directory.path) (errno \(errno)). Allow access to the Downloads folder in System Settings → Privacy & Security → Files and Folders."))
                return
            }

            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend],
                queue: queue
            )
            newSource.setEventHandler { [weak self] in
                self?.scheduleScan(after: 0.3)
            }
            newSource.setCancelHandler {
                close(descriptor)
            }
            source = newSource
            newSource.resume()

            scan()
        }
    }

    public func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
            pendingRescan?.cancel()
            pendingRescan = nil
            candidates.removeAll()
        }
    }

    /// Forget the baseline so the next `start()` treats current files as old again.
    public func resetHistory() {
        queue.async { [self] in
            defaults.removeObject(forKey: processedKey)
            defaults.removeObject(forKey: baselineKey)
            processed.removeAll()
        }
    }

    // MARK: - Scanning (on `queue`)

    private func scheduleScan(after delay: TimeInterval) {
        pendingRescan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingRescan = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scan() {
        guard source != nil else { return }

        let now = Date()
        var stillWaiting = false
        var seenPaths = Set<String>()

        for url in heicFiles() {
            let path = url.standardizedFileURL.path
            seenPaths.insert(path)
            guard let fingerprint = fingerprint(of: url) else {
                // Empty file: still being created (AirDrop does this). Look again soon.
                stillWaiting = true
                continue
            }
            guard !processed.contains(fingerprint) else {
                candidates[path] = nil
                continue
            }

            // Wait until the file has looked the same for `stabilityInterval`.
            guard let candidate = candidates[path], candidate.fingerprint == fingerprint else {
                candidates[path] = (fingerprint, now)
                stillWaiting = true
                continue
            }
            guard now.timeIntervalSince(candidate.firstSeen) >= stabilityInterval else {
                stillWaiting = true
                continue
            }

            do {
                let output = try converter.convert(sourceURL: url, fileManager: fileManager)
                markProcessed(fingerprint, path: path)
                onEvent(.converted(source: url, output: output))
            } catch HEICAutoConverterError.incomplete {
                candidates[path] = (fingerprint, now)
                stillWaiting = true
            } catch {
                let attempts = (failures[path] ?? 0) + 1
                failures[path] = attempts
                if attempts >= maxAttempts {
                    markProcessed(fingerprint, path: path)
                    onEvent(.failed(source: url, message: error.localizedDescription))
                } else {
                    candidates[path] = (fingerprint, now)
                    stillWaiting = true
                }
            }
        }

        candidates = candidates.filter { seenPaths.contains($0.key) }
        pruneProcessed(existingPaths: seenPaths)

        if stillWaiting {
            scheduleScan(after: stabilityInterval)
        }
    }

    private func markProcessed(_ fingerprint: String, path: String) {
        processed.insert(fingerprint)
        candidates[path] = nil
        failures[path] = nil
        saveProcessed()
    }

    /// Drop history for files that are gone, so the stored list does not grow forever.
    private func pruneProcessed(existingPaths: Set<String>) {
        let before = processed.count
        processed = processed.filter { existingPaths.contains(Self.path(fromFingerprint: $0)) }
        if processed.count != before {
            saveProcessed()
        }
    }

    private func saveProcessed() {
        defaults.set(Array(processed), forKey: processedKey)
    }

    private func heicFiles() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        )) ?? []
        return urls.filter { url in
            HEICAutoConverter.isHEIC(url)
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    /// `path|size|mtime` — changes if the file is replaced by another one with the same name.
    private func fingerprint(of url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, size > 0 else {
            return nil
        }
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)|\(size)|\(Int(modified))"
    }

    private static func path(fromFingerprint fingerprint: String) -> String {
        let parts = fingerprint.split(separator: "|", omittingEmptySubsequences: false)
        return parts.dropLast(2).joined(separator: "|")
    }
}
