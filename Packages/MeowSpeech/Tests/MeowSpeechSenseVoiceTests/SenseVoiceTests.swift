import AVFoundation
import Foundation
@testable import MeowSpeechSenseVoice
import Testing

@Test("SenseVoice int8 layout contains only the required CoreML closure")
func senseVoiceInt8Layout() {
    let layout = SenseVoiceModelLayout(precision: .int8)
    #expect(layout.requiredRelativePaths == [
        "SenseVoicePreprocessor.mlmodelc/coremldata.bin",
        "SenseVoicePreprocessor.mlmodelc/model.mil",
        "SenseVoicePreprocessor.mlmodelc/weights/weight.bin",
        "SenseVoiceSmall_int8.mlmodelc/coremldata.bin",
        "SenseVoiceSmall_int8.mlmodelc/model.mil",
        "SenseVoiceSmall_int8.mlmodelc/weights/weight.bin",
        "vocab.json",
    ])
}

@Test("SenseVoice CTC decode preserves SentencePiece boundaries")
func senseVoiceCtcDecode() {
    let text = decodeCtcTokenIDs(
        [1, 2, 3],
        vocabulary: [1: "▁hello", 2: "▁world", 3: "!"]
    )
    #expect(text == "hello world!")
}

@Test("Installed SenseVoice CoreML model transcribes a WAV fixture")
func senseVoiceModelSmokeTest() async throws {
    guard let modelPath = ProcessInfo.processInfo.environment["MEOW_SENSEVOICE_MODEL_DIR"] else {
        return
    }

    let audioURL: URL
    if let externalAudioPath = ProcessInfo.processInfo.environment["MEOW_SENSEVOICE_AUDIO"] {
        audioURL = URL(fileURLWithPath: externalAudioPath)
    } else if let bundledAudioURL = Bundle.module.url(
        forResource: "01-validation-request-21.4s",
        withExtension: "wav"
    ) {
        audioURL = bundledAudioURL
    } else {
        throw NSError(domain: "MeowSpeechTests", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "The fixed SenseVoice audio fixture is missing"
        ])
    }

    let file = try AVAudioFile(forReading: audioURL)
    guard file.processingFormat.sampleRate == 16_000 else {
        throw NSError(domain: "MeowSpeechTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "SenseVoice fixture must be 16 kHz"
        ])
    }
    // The fixture begins with a short lead-in, so keep the full recording for
    // a meaningful transcription assertion. The test uses CPU-only inference
    // to avoid making CI depend on Neural Engine graph specialization.
    let frameCount = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: frameCount
    ) else {
        throw NSError(domain: "MeowSpeechTests", code: 2)
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else {
        throw NSError(domain: "MeowSpeechTests", code: 3)
    }
    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))

    let recognizer = SenseVoiceRecognizer(
        modelDirectory: URL(fileURLWithPath: modelPath),
        computePolicy: .cpuOnly
    )
    let result = try await recognizer.transcribe(samples: samples, sampleRate: 16_000)
    #expect(!result.text.isEmpty)
}
