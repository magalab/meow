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
        .executableTarget(
            name: "Meow",
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
