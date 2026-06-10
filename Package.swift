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
