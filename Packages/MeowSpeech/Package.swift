// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeowSpeech",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MeowSpeechCore", targets: ["MeowSpeechCore"]),
        .library(name: "MeowSpeechSenseVoice", targets: ["MeowSpeechSenseVoice"]),
    ],
    targets: [
        .target(
            name: "MeowSpeechCore",
            path: "Sources/MeowSpeechCore"
        ),
        .target(
            name: "MeowSpeechSenseVoice",
            dependencies: ["MeowSpeechCore"],
            path: "Sources/MeowSpeechSenseVoice"
        ),
        .testTarget(
            name: "MeowSpeechCoreTests",
            dependencies: ["MeowSpeechCore"],
            path: "Tests/MeowSpeechCoreTests"
        ),
        .testTarget(
            name: "MeowSpeechSenseVoiceTests",
            dependencies: ["MeowSpeechSenseVoice"],
            path: "Tests/MeowSpeechSenseVoiceTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
