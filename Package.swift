// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Image_Crab_Converter",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ImageCrabConverterCore",
            targets: ["ImageCrabConverterCore"]
        ),
        .executable(
            name: "Image_Crab_Converter",
            targets: ["Image_Crab_Converter"]
        )
    ],
    targets: [
        .target(
            name: "ImageCrabConverterCore",
            path: "Sources/ImageCrabConverterCore"
        ),
        .executableTarget(
            name: "Image_Crab_Converter",
            dependencies: ["ImageCrabConverterCore"],
            path: "Sources/Image_Crab_Converter"
        ),
        .executableTarget(
            name: "ImageCrabConverterAutoTests",
            dependencies: ["ImageCrabConverterCore"],
            path: "TestsRunner"
        )
    ]
)
