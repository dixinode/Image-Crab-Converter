import SwiftUI

struct RenamePatternView: View {
    @Binding var enabled: Bool
    @Binding var pattern: String
    @Binding var startNumber: Int
    let preview: [String]
    let notice: String?
    let error: String?

    private let tokenExamples: [String] = [
        "{n}",
        "{n:4}",
        "{name}",
        "{date}",
        "{time}",
        "{datetime}",
        "{ext}",
        "{width}",
        "{height}"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable rename", isOn: $enabled)

            TextField("Pattern", text: $pattern)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)

            if let error {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CoffeePalette.destructive)
            }

            HStack {
                Text("Start")
                Stepper(value: $startNumber, in: 1...999_999) {
                    Text("\(startNumber)")
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Tokens")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CoffeePalette.textSecondary)

                Text(tokenExamples.joined(separator: "   "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(CoffeePalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Examples: photo_{n:3}, {name}_{date}, export_{datetime}_{n}")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(CoffeePalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice {
                Text(notice)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CoffeePalette.textTertiary)
            }

            if !preview.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CoffeePalette.textSecondary)
                    ForEach(preview, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
        }
    }
}
