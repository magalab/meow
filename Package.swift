// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Meow",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Meow", targets: ["Meow"]),
    ],
    targets: [
        .executableTarget(
            name: "Meow",
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
