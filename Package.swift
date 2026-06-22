// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Meow",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "Meow", targets: ["Meow"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "SherpaOnnxC",
            path: "Vendor/SherpaOnnx.xcframework"
        ),
        .binaryTarget(
            name: "ONNXRuntime",
            path: "Vendor/ONNXRuntime.xcframework"
        ),
        .executableTarget(
            name: "Meow",
            dependencies: [
                "SherpaOnnxC",
                "ONNXRuntime",
                .product(name: "SotoS3", package: "soto"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "MeowTests",
            dependencies: ["Meow"],
            path: "Tests"
        ),
    ]
)
