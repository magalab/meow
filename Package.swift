// swift-tools-version: 6.0
import Foundation
import PackageDescription

let isVoiceEdition = ProcessInfo.processInfo.environment["MEOW_EDITION"] == "voice"
let executableName = isVoiceEdition ? "Miao" : "Meow"

let voiceSources = [
    "Services/SpeechHistoryStore.swift",
    "Services/SpeechModelStore.swift",
    "Services/SpeechRecognizerFactory.swift",
    "Services/SpeechRecognitionService.swift",
    "Services/SpeechSynthesisService.swift",
    "Services/SpeechSynthesizerFactory.swift",
    "Services/SystemSpeechSynthesizer.swift",
    "Services/TtsAudioPlayer.swift",
    "Services/TtsModelStore.swift",
    "Views/Speech/SpeechOverlayView.swift",
    "Views/Preferences/SpeechPreferencesView.swift",
    "Views/Preferences/TtsPreferencesView.swift",
]

var executableDependencies: [Target.Dependency] = [
    .target(name: "WhiteboardFeature"),
    .product(name: "MeowSpeechCore", package: "MeowSpeech"),
    .product(name: "GRDB", package: "GRDB.swift"),
    .product(name: "SotoS3", package: "soto"),
]
if isVoiceEdition {
    executableDependencies += [
        .product(name: "MeowSpeechSenseVoice", package: "MeowSpeech"),
        .product(name: "MeowSpeechMossTTS", package: "MeowSpeech"),
    ]
}

let testSwiftSettings: [SwiftSetting] = isVoiceEdition ? [.define("MEOW_VOICE")] : []
var executableLinkerSettings: [LinkerSetting] = [
    .linkedFramework("IOKit"),
    .linkedFramework("Metal")
]
if isVoiceEdition {
    executableLinkerSettings.append(.linkedLibrary("c++"))
}

let targets: [Target] = [
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
        linkerSettings: executableLinkerSettings
    ),
    .testTarget(
        name: "MeowTests",
        dependencies: [
            .target(name: executableName)
        ],
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
        .package(path: "Packages/MeowSpeech"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.8.0"),
        .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    ],
    targets: targets
)
