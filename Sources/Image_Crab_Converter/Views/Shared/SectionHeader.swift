import SwiftUI

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CoffeePalette.textSecondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
