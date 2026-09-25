import MeowSpeechCore

/// Reserved for the MOSS-TTS-Nano extraction.
///
/// The public streaming contract is intentionally available before the CoreML
/// implementation lands. This keeps Meow independent from model-specific TTS
/// types while the acoustic model is still being evaluated.
public struct MossTTSNanoSynthesizer: SpeechSynthesizer {
    public init() {}

    public func synthesize(
        text: String,
        voice: VoiceProfile?
    ) -> AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: SpeechError.unsupported(
                    "MOSS-TTS-Nano has not been enabled in this build."
                )
            )
        }
    }
}
