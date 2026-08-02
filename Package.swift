// swift-tools-version: 6.0
import Foundation
import PackageDescription

let isVoiceEdition = ProcessInfo.processInfo.environment["MEOW_EDITION"] == "voice"
let executableName = isVoiceEdition ? "Miao" : "Meow"

let voiceSources = [
    "Services/SherpaOnnxRecognizer.swift",
    "Services/SherpaOnnxSynthesizer.swift",
    "Services/SpeechHistoryStore.swift",
    "Services/SpeechModelStore.swift",
    "Services/SpeechRecognitionService.swift",
    "Services/SpeechSynthesisService.swift",
    "Services/TtsAudioPlayer.swift",
    "Services/TtsModelStore.swift",
    "Views/SpeechOverlayView.swift",
    "Views/SpeechPreferencesView.swift",
    "Views/TtsPreferencesView.swift",
]

var executableDependencies: [Target.Dependency] = [
    .target(name: "WhiteboardFeature"),
    .product(name: "SotoS3", package: "soto"),
]
if isVoiceEdition {
    executableDependencies += ["SherpaOnnxC", "ONNXRuntime"]
}

let testSwiftSettings: [SwiftSetting] = isVoiceEdition ? [.define("MEOW_VOICE")] : []

let targets: [Target] = [
    .binaryTarget(name: "SherpaOnnxC", path: "Vendor/SherpaOnnx.xcframework"),
    .binaryTarget(name: "ONNXRuntime", path: "Vendor/ONNXRuntime.xcframework"),
    .target(
        name: "WhiteboardFeature",
        path: "Modules/WhiteboardFeature/Sources",
        resources: [.process("Resources")]
    ),
    .executableTarget(
        name: executableName,
        dependencies: executableDependencies,
        path: "Sources",
        exclude: isVoiceEdition ? [] : voiceSources,
        resources: [.process("Resources")],
        swiftSettings: isVoiceEdition ? [.define("MEOW_VOICE")] : [],
        linkerSettings: isVoiceEdition ? [.linkedLibrary("c++")] : []
    ),
    .testTarget(
        name: "MeowTests",
        dependencies: [.target(name: executableName)],
        path: "Tests",
        swiftSettings: testSwiftSettings
    ),
    .testTarget(
        name: "WhiteboardFeatureTests",
        dependencies: ["WhiteboardFeature"],
        path: "Modules/WhiteboardFeature/Tests"
    ),
]

let package = Package(
    name: "Meow",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: executableName, targets: [executableName])],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    ],
    targets: targets
)
