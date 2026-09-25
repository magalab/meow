import AVFoundation
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao

@Test("SenseVoice downloads accept the CoreML model staging layout")
func senseVoiceDownloadStagingValidation() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-ASR-Test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for relativePath in SpeechModelKind.senseVoice.requiredRelativePaths {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(to: fileURL)
    }

    try SpeechModelStore.validateStagingContents(for: .senseVoice, in: root)

    try FileManager.default.removeItem(
        at: root.appendingPathComponent("vocab.json")
    )
    #expect(throws: (any Error).self) {
        try SpeechModelStore.validateStagingContents(for: .senseVoice, in: root)
    }
}

@Test("Legacy speech model settings migrate to SenseVoice")
func legacySpeechModelSettingMigration() throws {
    let settings = try JSONDecoder().decode(
        SpeechSettings.self,
        from: Data("{\"model\":\"parakeetEnglish\"}".utf8)
    )

    #expect(settings.model == .senseVoice)
}

@Test("SenseVoice manifest is pinned and has unique verified artifacts")
func senseVoiceManifestIsPinned() {
    let artifacts = SpeechModelKind.senseVoice.manifest.artifacts
    #expect(SpeechModelKind.senseVoice.manifest.version.count == 40)
    #expect(Set(artifacts.map(\.relativePath)).count == artifacts.count)
    #expect(artifacts.allSatisfy { $0.sha256.count == 64 })
    #expect(artifacts.allSatisfy { $0.remoteURL.absoluteString.contains("/resolve/") })
}

@Test("Legacy Matcha TTS settings migrate to system voices")
@MainActor
func legacyTtsSettingsMigration() throws {
    let settings = try JSONDecoder().decode(
        TtsSettings.self,
        from: Data("{\"model\":\"matchaChineseEnglish\"}".utf8)
    )

    #expect(settings.model == .system)
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

@Test("System voice synthesis emits PCM audio (opt-in)")
func systemVoiceSynthesisSmokeTest() async throws {
    guard ProcessInfo.processInfo.environment["MEOW_SYSTEM_TTS_SMOKE"] == "1" else {
        return
    }

    var samples: [Float] = []
    var sampleRate = 0
    for try await chunk in SystemSpeechSynthesizer().synthesize(
        text: "Hello from Meow.",
        voice: nil
    ) {
        sampleRate = chunk.sampleRate
        samples.append(contentsOf: chunk.samples)
    }
    #expect(sampleRate > 0)
    #expect(!samples.isEmpty)
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

#endif
