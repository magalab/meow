// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeowSpeech",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MeowSpeechCore", targets: ["MeowSpeechCore"]),
        .library(name: "MeowSpeechSenseVoice", targets: ["MeowSpeechSenseVoice"]),
        .library(name: "MeowSpeechMossTTS", targets: ["MeowSpeechMossTTS"]),
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
        .target(
            name: "MeowSpeechMossTTS",
            dependencies: ["MeowSpeechCore"],
            path: "Sources/MeowSpeechMossTTS"
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
        .testTarget(
            name: "MeowSpeechMossTTSTests",
            dependencies: ["MeowSpeechMossTTS"],
            path: "Tests/MeowSpeechMossTTSTests"
        ),
    ]
)
