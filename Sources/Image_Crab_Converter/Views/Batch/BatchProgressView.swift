import SwiftUI

struct BatchProgressView: View {
    let current: Int
    let total: Int
    let currentFile: String
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(current), total: Double(max(1, total)))
                .tint(CoffeePalette.accentPrimary)

            Text("Processing \(currentFile)... (\(current) / \(total))")
                .font(.system(size: 12))
                .foregroundStyle(CoffeePalette.textSecondary)

            Button("Cancel", action: cancelAction)
                .buttonStyle(CoffeeButton(prominent: false))
        }
    }
}
