import AppKit
import SwiftUI

/// Contents of the menu bar item.
struct AutoConvertMenu: View {
    static let mainWindowID = "main"

    @ObservedObject var controller: AutoConvertController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(
            "Auto-convert HEIC in Downloads",
            isOn: Binding(get: { controller.isEnabled }, set: { controller.setEnabled($0) })
        )

        Text("JPG · quality 100% · 45% size")

        Divider()

        if controller.recent.isEmpty {
            Text("No conversions yet")
        } else {
            Text("Recent")
            ForEach(controller.recent) { entry in
                if let output = entry.output {
                    Button("✓ \(output.lastPathComponent)") {
                        controller.reveal(entry)
                    }
                } else {
                    Text("⚠︎ \(entry.sourceName): \(entry.error ?? "error")")
                }
            }
        }

        Divider()

        Button("Open Downloads") {
            controller.openDownloads()
        }

        Button("Open Image Crab Converter") {
            openWindow(id: Self.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
