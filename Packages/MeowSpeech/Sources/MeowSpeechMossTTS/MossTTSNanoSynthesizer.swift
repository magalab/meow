import Foundation
import MeowSpeechCore

/// Package-level MOSS synthesizer. The no-argument initializer remains an
/// explicit placeholder for callers that have not supplied a model directory;
/// the model-directory initializer enables the real CoreML path.
public struct MossTTSNanoSynthesizer: PreparableSpeechSynthesizer {
    private let loader: MossTTSNanoModelLoader?
    private let defaultVoiceID: String
    private let maxFrames: Int
    private let greedy: Bool
    private let seed: UInt64

    public init() {
        loader = nil
        defaultVoiceID = "zh_1"
        maxFrames = 375
        greedy = false
        seed = 0x4D_4F_53_53
    }

    public init(
        modelDirectory: URL,
        defaultVoiceID: String = "zh_1",
        maxFrames: Int = 375,
        greedy: Bool = false,
        seed: UInt64 = 0x4D_4F_53_53,
        computePolicy: MossTTSNanoComputePolicy = .cpuAndGPU
    ) {
        loader = MossTTSNanoModelLoader(
            modelDirectory: modelDirectory,
            computePolicy: computePolicy
        )
        self.defaultVoiceID = defaultVoiceID
        self.maxFrames = maxFrames
        self.greedy = greedy
        self.seed = seed
    }

    public func prepare() async throws {
        guard let loader else { return }
        try await loader.prepare()
        guard await loader.beginInferenceWarmup() else { return }
        do {
            let configuration = try await loader.configuration()
            let textTokenIDs = try await loader.tokenize("你好")
            guard !textTokenIDs.isEmpty else { return }
            let promptAudioCodes = try await loader.presetVoiceCodes(for: defaultVoiceID)
            let prompt = try MossTTSNanoPromptBuilder(configuration: configuration)
                .buildVoiceClonePrompt(
                    promptAudioCodes: promptAudioCodes,
                    textTokenIDs: textTokenIDs
                )
            _ = try await loader.generateAudio(
                for: prompt,
                maxFrames: 2,
                greedy: true,
                seed: seed,
                maximumFramesPerCall: 2
            ) { _ in }
            await loader.finishInferenceWarmup(success: true)
        } catch {
            await loader.finishInferenceWarmup(success: false)
            // Loading remains successful even when a device-specific CoreML
            // warmup is unavailable. The first real synthesis can still
            // report its normal inference error with the full context.
            NSLog("MOSS-TTS-Nano inference prewarm failed: %@", error.localizedDescription)
        }
    }

    public func synthesize(
        text: String,
        voice: VoiceProfile?
    ) -> AsyncThrowingStream<AudioChunk, Error> {
        guard let loader else {
            return AsyncThrowingStream { continuation in
                continuation.finish(
                    throwing: SpeechError.unsupported(
                        "MOSS-TTS-Nano has not been enabled in this build."
                    )
                )
            }
        }

        let requestedVoiceID = voice?.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceID = requestedVoiceID.flatMap { $0.isEmpty ? nil : $0 } ?? defaultVoiceID
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try Task.checkCancellation()
                    try await loader.prepare()
                    let configuration = try await loader.configuration()
                    let textTokenIDs = try await loader.tokenize(text)
                    guard !textTokenIDs.isEmpty else {
                        throw SpeechError.invalidAudio("MOSS-TTS-Nano text is empty after tokenization.")
                    }
                    let promptAudioCodes = try await loader.presetVoiceCodes(for: voiceID)
                    let prompt = try MossTTSNanoPromptBuilder(configuration: configuration)
                        .buildVoiceClonePrompt(
                            promptAudioCodes: promptAudioCodes,
                            textTokenIDs: textTokenIDs
                        )
                    let emittedFrameCount = try await loader.generateAudio(
                        for: prompt,
                        maxFrames: maxFrames,
                        greedy: greedy,
                        seed: seed,
                        maximumFramesPerCall: 4
                    ) { audio in
                        guard audio.frameCount > 0 else { return }
                        let samples = Self.downmix(audio)
                        let chunkSize = 3_840
                        var start = 0
                        while start < samples.count {
                            let end = min(start + chunkSize, samples.count)
                            continuation.yield(
                                AudioChunk(
                                    samples: Array(samples[start..<end]),
                                    sampleRate: audio.sampleRate,
                                    isFinal: false
                                )
                            )
                            start = end
                        }
                    }
                    guard emittedFrameCount > 0 else {
                        throw SpeechError.inferenceFailed("MOSS-TTS-Nano produced no audio.")
                    }
                    try Task.checkCancellation()
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: SpeechError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func downmix(_ audio: MossTTSNanoAudio) -> [Float] {
        guard audio.channels.count > 1 else { return audio.channels.first ?? [] }
        let count = audio.frameCount
        return (0..<count).map { index in
            audio.channels.reduce(Float.zero) { partial, channel in
                partial + channel[index]
            } / Float(audio.channels.count)
        }
    }
}
