import AppKit
import Foundation
import ImageCrabConverterCore
import UserNotifications

/// Owns the Downloads watcher and exposes its state to the menu bar item.
@MainActor
final class AutoConvertController: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let sourceName: String
        let output: URL?
        let error: String?
    }

    private static let enabledKey = "autoConvert.enabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var recent: [Entry] = []

    let downloadsURL: URL
    private var watcher: FolderAutoConverter?
    private var terminationActivity: NSObjectProtocol?

    init() {
        downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

        // On by default: that's the whole point of the feature.
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)

        if isEnabled {
            startWatching()
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        enabled ? startWatching() : stopWatching()
    }

    func openDownloads() {
        NSWorkspace.shared.open(downloadsURL)
    }

    func reveal(_ entry: Entry) {
        guard let output = entry.output else { return }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    private func startWatching() {
        guard watcher == nil else { return }

        let watcher = FolderAutoConverter(directory: downloadsURL) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.watcher = watcher
        watcher.start()

        // The bundle allows automatic termination; a background watcher must not be killed
        // just because no window is open.
        terminationActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Watching Downloads for HEIC photos"
        )

        requestNotificationPermission()
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
        if let terminationActivity {
            ProcessInfo.processInfo.endActivity(terminationActivity)
            self.terminationActivity = nil
        }
    }

    private func handle(_ event: FolderAutoConverter.Event) {
        let entry: Entry
        switch event {
        case let .converted(source, output):
            entry = Entry(date: Date(), sourceName: source.lastPathComponent, output: output, error: nil)
            notify(title: "HEIC → JPG", body: "\(source.lastPathComponent) → \(output.lastPathComponent)")
        case let .failed(source, message):
            entry = Entry(date: Date(), sourceName: source.lastPathComponent, output: nil, error: message)
            notify(title: "Auto-convert failed", body: message)
        }
        recent.insert(entry, at: 0)
        if recent.count > 10 {
            recent.removeLast(recent.count - 10)
        }
    }

    // MARK: - Notifications

    /// UNUserNotificationCenter crashes when the binary runs outside an .app bundle
    /// (e.g. `swift run`), so only use it when we have a bundle identifier.
    private var canNotify: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
