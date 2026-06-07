import Foundation
import SherpaOnnxC

struct SpeechRecognitionResult: Sendable {
    let text: String
    let language: String?
}

enum SherpaOnnxRecognizerError: LocalizedError, Sendable {
    case invalidModel
    case failedToCreateRecognizer
    case failedToCreateStream
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "The speech recognition model is incomplete."
        case .failedToCreateRecognizer:
            return "The speech recognition model could not be loaded."
        case .failedToCreateStream:
            return "The speech recognition stream could not be created."
        case .emptyResult:
            return "No speech was recognized."
        }
    }
}

final class SherpaOnnxRecognizer: @unchecked Sendable {
    private let recognizer: OpaquePointer
    private let lock = NSLock()

    init(model: SpeechModelKind, modelURL: URL, tokensURL: URL) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: tokensURL.path)
        else {
            throw SherpaOnnxRecognizerError.invalidModel
        }

        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = 16_000
        config.feat_config.feature_dim = 80
        config.model_config.num_threads = Int32(max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4)))
        config.model_config.debug = 0

        let created: OpaquePointer? = modelURL.path.withCString { modelPath in
            tokensURL.path.withCString { tokensPath in
                "cpu".withCString { provider in
                    config.model_config.provider = provider
                    config.model_config.tokens = tokensPath
                    return "greedy_search".withCString { decodingMethod in
                        config.decoding_method = decodingMethod
                        switch model.recognitionFlavor {
                        case .senseVoice:
                            return "auto".withCString { language in
                                config.model_config.sense_voice.model = modelPath
                                config.model_config.sense_voice.language = language
                                config.model_config.sense_voice.use_itn = 1
                                return SherpaOnnxCreateOfflineRecognizer(&config)
                            }
                        case .nemoCtc:
                            config.model_config.nemo_ctc.model = modelPath
                            return SherpaOnnxCreateOfflineRecognizer(&config)
                        }
                    }
                }
            }
        }

        guard let created else {
            throw SherpaOnnxRecognizerError.failedToCreateRecognizer
        }
        recognizer = created
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    func recognize(samples: [Float], sampleRate: Int) throws -> SpeechRecognitionResult {
        lock.lock()
        defer { lock.unlock() }

        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            throw SherpaOnnxRecognizerError.failedToCreateStream
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(
                stream,
                Int32(sampleRate),
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            throw SherpaOnnxRecognizerError.emptyResult
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

        let text = result.pointee.text.map(String.init(cString:))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw SherpaOnnxRecognizerError.emptyResult
        }

        let language = result.pointee.lang.map(String.init(cString:))
        return SpeechRecognitionResult(text: text, language: language)
    }
}
