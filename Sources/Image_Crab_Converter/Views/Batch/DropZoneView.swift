import SwiftUI

struct DropZoneView: View {
    let browseAction: () -> Void

    var body: some View {
        Button(action: browseAction) {
            VStack(spacing: 10) {
                Text("🦀")
                    .font(.system(size: 36))
                Text("Drop images here")
                    .font(.system(size: 14, weight: .semibold))
                Text("or click to browse")
                    .font(.system(size: 12))
                    .foregroundStyle(CoffeePalette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(CoffeePalette.surfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CoffeePalette.border, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
