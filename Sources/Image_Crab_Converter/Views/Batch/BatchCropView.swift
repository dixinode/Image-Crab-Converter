import ImageCrabConverterCore
import SwiftUI

struct BatchCropView: View {
    @Binding var enabled: Bool
    @Binding var mode: CropOptions.Mode
    @Binding var anchor: ImageCrabConverterCore.AnchorPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Enable crop", isOn: $enabled)

            HStack(spacing: 8) {
                Text("Mode")
                    .frame(width: 52, alignment: .leading)

                Picker("Mode", selection: Binding<Int>(
                    get: {
                        switch mode {
                        case .fixedSize:
                            return 0
                        case .aspectRatio:
                            return 1
                        }
                    },
                    set: { (value: Int) in
                        if value == 0 {
                            mode = .fixedSize(width: 800, height: 600)
                        } else {
                            mode = .aspectRatio(width: 16, height: 9)
                        }
                    }
                )) {
                    Text("Fixed Size").tag(0)
                    Text("Aspect Ratio").tag(1)
                }
                .labelsHidden()
            }

            switch mode {
            case let .fixedSize(width, height):
                HStack(spacing: 8) {
                    Text("Size")
                        .frame(width: 52, alignment: .leading)

                    Stepper("W \(width)", value: Binding(
                        get: { width },
                        set: { mode = .fixedSize(width: $0, height: height) }
                    ), in: 1...50_000)

                    Stepper("H \(height)", value: Binding(
                        get: { height },
                        set: { mode = .fixedSize(width: width, height: $0) }
                    ), in: 1...50_000)
                }
            case let .aspectRatio(width, height):
                HStack(spacing: 8) {
                    Text("Ratio")
                        .frame(width: 52, alignment: .leading)

                    Stepper("W \(width)", value: Binding(
                        get: { width },
                        set: { mode = .aspectRatio(width: $0, height: height) }
                    ), in: 1...500)

                    Stepper("H \(height)", value: Binding(
                        get: { height },
                        set: { mode = .aspectRatio(width: width, height: $0) }
                    ), in: 1...500)
                }
            }

            HStack(spacing: 8) {
                Text("Anchor")
                    .frame(width: 52, alignment: .leading)

                Picker("Anchor", selection: $anchor) {
                    ForEach(ImageCrabConverterCore.AnchorPoint.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .labelsHidden()
            }
        }
    }
}
