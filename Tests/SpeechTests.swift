import AVFoundation
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao

@Test("SenseVoice downloads accept the flat file staging layout")
func senseVoiceDownloadStagingValidation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-ASR-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("model".utf8).write(to: root.appendingPathComponent("model.int8.onnx"))
    try Data("tokens".utf8).write(to: root.appendingPathComponent("tokens.txt"))

    try SpeechModelStore.validateStagingContents(for: .senseVoice, in: root)

    try FileManager.default.removeItem(at: root.appendingPathComponent("tokens.txt"))
    #expect(throws: (any Error).self) {
        try SpeechModelStore.validateStagingContents(for: .senseVoice, in: root)
    }
}

@Test("TTS model manifest identifies a complete installation")
@MainActor
func ttsModelManifestValidation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-TTS-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let model = TtsModelKind.matchaChineseEnglish
    let modelDirectory = root.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
    let store = TtsModelStore(modelsRootDirectory: root)
    #expect(!store.isInstalled)

    for relativePath in model.requiredRelativePaths {
        let url = modelDirectory.appendingPathComponent(relativePath)
        if url.pathExtension.isEmpty {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data().write(to: url)
        }
    }
    store.refreshState()

    #expect(store.isInstalled)
    #expect(store.state == .installed)
    #expect(model.archive.fileName == "matcha-icefall-zh-en.tar.bz2")
    #expect(model.additionalFiles.map(\.relativePath) == ["vocos-16khz-univ.onnx"])
}

@Test("TTS text normalization and chunking preserve mixed-language content")
func ttsTextChunking() {
    let normalized = SpeechSynthesisService.normalizedText("  Hello   世界。\n下一句  ")
    #expect(normalized == "Hello 世界。下一句")
    #expect(SpeechSynthesisService.normalizedText("你好，") == "你好")
    #expect(
        SpeechSynthesisService.normalizedText("你好， 我是你的好朋友，小汪.")
            == "你好，我是你的好朋友，小汪。"
    )
    #expect(
        SpeechSynthesisService.normalizedText("按 ⌘S 保存，或用 ⌥D 翻译。")
            == "按 Command plus essay 保存，或用 Option plus deep 翻译。"
    )

    let longText = Array(repeating: "中文 and English sentence。", count: 40).joined(separator: " ")
    let chunks = SpeechSynthesisService.chunks(from: longText, maximumLength: 120)
    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { !$0.isEmpty })
    #expect(chunks.joined(separator: " ").contains("中文"))
    #expect(chunks.joined(separator: " ").contains("English"))

    let chineseChunks = SpeechSynthesisService.chunks(from: "你好，我是你的好朋友，小汪。", maximumLength: 120)
    #expect(chineseChunks == ["你好，我是你的好朋友，小汪。"])
}

@Test("TTS WAV export preserves sample rate and duration")
func ttsWAVExport() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-TTS-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let result = TtsAudioResult(
        samples: Array(repeating: 0.1, count: 2_400),
        sampleRate: 24_000,
        text: "test",
        voiceID: 0
    )

    try SpeechSynthesisService.writeWAV(result, to: url)
    let audioFile = try AVAudioFile(forReading: url)
    #expect(Int(audioFile.fileFormat.sampleRate) == 24_000)
    #expect(audioFile.length == 2_400)
    #expect(abs(result.duration - 0.1) < 0.0001)
}

@Test("Installed Matcha model synthesizes Chinese and English")
func installedMatchaModelSmokeTest() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["MEOW_TTS_MODEL_DIR"] else {
        return
    }
    let synthesizer = try SherpaOnnxSynthesizer(
        model: .matchaChineseEnglish,
        modelDirectory: URL(fileURLWithPath: modelPath)
    )
    let result = try await synthesizer.synthesize(
        text: "Hello from Meow. 你好，欢迎使用离线语音合成。",
        voiceID: 0,
        speed: 1,
        progress: { _ in }
    )
    #expect(result.sampleRate == 16_000)
    #expect(result.samples.count > 16_000)
}
#endif
