import SwiftUI

enum CoffeePalette {
    static let backgroundPrimary = Color(hex: "F5EFE6")
    static let backgroundSecondary = Color(hex: "EDE4D6")
    static let backgroundTertiary = Color(hex: "E0D5C3")
    static let surfaceElevated = Color(hex: "FAF7F2")

    static let accentPrimary = Color(hex: "8B5E3C")
    static let accentHover = Color(hex: "6F4A2F")
    static let accentSecondary = Color(hex: "C4956A")

    static let textPrimary = Color(hex: "2C1D12")
    static let textSecondary = Color(hex: "6B5040")
    static let textTertiary = Color(hex: "A08060")

    static let border = Color(hex: "D4C5B0")
    static let destructive = Color(hex: "B85C38")
    static let success = Color(hex: "6B8C5A")
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
