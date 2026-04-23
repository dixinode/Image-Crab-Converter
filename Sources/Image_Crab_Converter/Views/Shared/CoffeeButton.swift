import SwiftUI

struct CoffeeButton: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : CoffeePalette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? (configuration.isPressed ? CoffeePalette.accentHover : CoffeePalette.accentPrimary) : CoffeePalette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CoffeePalette.border, lineWidth: 1)
            )
    }
}
