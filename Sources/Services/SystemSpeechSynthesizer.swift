@preconcurrency import AVFoundation
import Foundation
import MeowSpeechCore

/// Uses the speech voices already installed in macOS while the extracted
/// MOSS-TTS-Nano backend is being integrated. It deliberately has no model or
/// third-party runtime dependency.
final class SystemSpeechSynthesizer: SpeechSynthesizer, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    func synthesize(
        text: String,
        voice: VoiceProfile?
    ) -> AsyncThrowingStream<AudioChunk, Error> {
        AsyncThrowingStream { continuation in
            Task { [self] in
                do {
                    let audio = try await self.synthesizeAudio(text: text, voice: voice)
                    continuation.yield(
                        AudioChunk(
                            samples: audio.samples,
                            sampleRate: audio.sampleRate,
                            isFinal: true
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func synthesizeAudio(
        text: String,
        voice: VoiceProfile? = nil
    ) async throws -> TtsAudioResult {
        try Task.checkCancellation()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: text, preferred: voice)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completion = SpeechBufferCompletion(continuation)
                synthesizer.write(utterance) { buffer in
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                        completion.fail(.invalidBuffer)
                        return
                    }

                    guard pcmBuffer.frameLength > 0 else {
                        do {
                            completion.succeed(try completion.collector.result(for: text))
                        } catch {
                            completion.fail((error as? SpeechSynthesisError) ?? .invalidBuffer)
                        }
                        return
                    }

                    do {
                        try completion.collector.append(pcmBuffer)
                    } catch {
                        completion.fail((error as? SpeechSynthesisError) ?? .invalidBuffer)
                    }
                }
            }
        } onCancel: {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private static func voice(
        for text: String,
        preferred: VoiceProfile?
    ) -> AVSpeechSynthesisVoice? {
        if let language = preferred?.language,
           let voice = AVSpeechSynthesisVoice(language: language) {
            return voice
        }
        let language = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            ? "zh-CN"
            : "en-US"
        return AVSpeechSynthesisVoice(language: language)
    }
}

private final class SpeechBufferCompletion: @unchecked Sendable {
    let collector = SpeechBufferCollector()
    private let lock = NSLock()
    private var didFinish = false
    private var continuation: CheckedContinuation<TtsAudioResult, Error>?

    init(_ continuation: CheckedContinuation<TtsAudioResult, Error>) {
        self.continuation = continuation
    }

    func succeed(_ value: TtsAudioResult) {
        finish(value: value, error: nil)
    }

    func fail(_ error: SpeechSynthesisError) {
        finish(value: nil, error: error)
    }

    private func finish(value: TtsAudioResult?, error: SpeechSynthesisError?) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        if let value {
            continuation?.resume(returning: value)
        } else if let error {
            continuation?.resume(throwing: error)
        }
    }
}

private final class SpeechBufferCollector: @unchecked Sendable {
    private var sampleRate = 0
    private var samples: [Float] = []

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let channel = buffer.floatChannelData?[0] else {
            throw SpeechSynthesisError.invalidBuffer
        }
        let rate = Int(buffer.format.sampleRate.rounded())
        guard rate > 0 else {
            throw SpeechSynthesisError.invalidBuffer
        }
        if sampleRate == 0 {
            sampleRate = rate
        } else if sampleRate != rate {
            throw SpeechSynthesisError.inconsistentSampleRate
        }
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func result(for text: String) throws -> TtsAudioResult {
        guard sampleRate > 0, !samples.isEmpty else {
            throw SpeechSynthesisError.emptyAudio
        }
        return TtsAudioResult(samples: samples, sampleRate: sampleRate, text: text, voiceID: 0)
    }
}

private enum SpeechSynthesisError: LocalizedError, Sendable {
    case invalidBuffer
    case inconsistentSampleRate
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .invalidBuffer, .inconsistentSampleRate:
            return L10n.ttsErrorGenerationFailed
        case .emptyAudio:
            return L10n.ttsErrorEmptyAudio
        }
    }
}
