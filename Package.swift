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
    "Views/Speech/SpeechOverlayView.swift",
    "Views/Preferences/SpeechPreferencesView.swift",
]

var executableDependencies: [Target.Dependency] = [
    .target(name: "WhiteboardFeature"),
    .target(name: "MeowClipboard"),
    .target(name: "MeowCapture"),
    .target(name: "MeowRecording"),
    .target(name: "MeowAI"),
    .target(name: "MeowLauncher"),
    .target(name: "MeowS3"),
]
if isVoiceEdition {
    executableDependencies += [
        .product(name: "MeowSpeechCore", package: "MeowSpeech"),
        .product(name: "MeowSpeechSenseVoice", package: "MeowSpeech"),
    ]
}

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.8.0"),
]
if isVoiceEdition {
    packageDependencies.insert(.package(path: "Packages/MeowSpeech"), at: 0)
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
        name: "MeowClipboard",
        dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
        ],
        path: "Modules/MeowClipboard/Sources"
    ),
    .target(
        name: "MeowCapture",
        path: "Modules/MeowCapture/Sources"
    ),
    .target(
        name: "MeowRecording",
        path: "Modules/MeowRecording/Sources"
    ),
    .target(
        name: "MeowAI",
        path: "Modules/MeowAI/Sources"
    ),
    .target(
        name: "MeowLauncher",
        dependencies: ["MeowClipboard"],
        path: "Modules/MeowLauncher/Sources"
    ),
    .target(
        name: "WhiteboardFeature",
        path: "Modules/WhiteboardFeature/Sources",
        resources: [.process("Resources")]
    ),
    .target(
        name: "MeowS3",
        path: "Sources/MeowS3"
    ),
    .executableTarget(
        name: executableName,
        dependencies: executableDependencies,
        path: "Sources",
        exclude: (isVoiceEdition ? [] : voiceSources) + ["MeowS3"],
        resources: [.process("Resources")],
        swiftSettings: isVoiceEdition ? [.define("MEOW_VOICE")] : [],
        linkerSettings: executableLinkerSettings
    ),
    .testTarget(
        name: "MeowTests",
        dependencies: [
            .target(name: executableName),
            .target(name: "MeowClipboard"),
            .target(name: "MeowCapture"),
            .target(name: "MeowRecording"),
            .target(name: "MeowAI")
        ],
        path: "Tests",
        exclude: ["MeowS3Tests"],
        swiftSettings: testSwiftSettings
    ),
    .testTarget(
        name: "WhiteboardFeatureTests",
        dependencies: ["WhiteboardFeature"],
        path: "Modules/WhiteboardFeature/Tests"
    ),
    .testTarget(
        name: "MeowClipboardTests",
        dependencies: ["MeowClipboard"],
        path: "Modules/MeowClipboard/Tests"
    ),
    .testTarget(
        name: "MeowCaptureTests",
        dependencies: ["MeowCapture"],
        path: "Modules/MeowCapture/Tests"
    ),
    .testTarget(
        name: "MeowRecordingTests",
        dependencies: ["MeowRecording"],
        path: "Modules/MeowRecording/Tests"
    ),
    .testTarget(
        name: "MeowAITests",
        dependencies: ["MeowAI"],
        path: "Modules/MeowAI/Tests"
    ),
    .testTarget(
        name: "MeowLauncherTests",
        dependencies: ["MeowLauncher", "MeowClipboard"],
        path: "Modules/MeowLauncher/Tests"
    ),
    .testTarget(
        name: "MeowS3Tests",
        dependencies: ["MeowS3"],
        path: "Tests/MeowS3Tests"
    ),
]

let package = Package(
    name: "Meow",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: executableName, targets: [executableName]),
        .library(name: "MeowS3", targets: ["MeowS3"]),
    ],
    dependencies: packageDependencies,
    targets: targets
)
