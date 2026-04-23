import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var navigationKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.windows.first?.title = "Image_Crab_Converter"
        installNavigationKeyMonitor()
        activateAppGently()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .viewerOpenFile, object: url)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let navigationKeyMonitor {
            NSEvent.removeMonitor(navigationKeyMonitor)
            self.navigationKeyMonitor = nil
        }
    }

    private func installNavigationKeyMonitor() {
        guard navigationKeyMonitor == nil else { return }

        navigationKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let blockedModifiers = event.modifierFlags.intersection([.command, .option, .control])
            guard blockedModifiers.isEmpty else {
                return event
            }

            let hasShift = event.modifierFlags.contains(.shift)

            if NSApp.keyWindow?.firstResponder is NSTextView {
                return event
            }

            switch event.keyCode {
            case 49:
                guard !hasShift else { return event }
                NotificationCenter.default.post(name: .viewerAdvanceToNextImage, object: nil)
                return nil
            case 124:
                NotificationCenter.default.post(name: .viewerAdvanceToNextImage, object: nil)
                return nil
            case 123:
                NotificationCenter.default.post(name: .viewerAdvanceToPreviousImage, object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func activateAppGently() {
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            if #available(macOS 11.0, *) {
                window.toolbarStyle = .unifiedCompact
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
