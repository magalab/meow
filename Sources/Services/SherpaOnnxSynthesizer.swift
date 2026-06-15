import Foundation
import SherpaOnnxC

enum SherpaOnnxSynthesizerError: LocalizedError, Sendable {
    case invalidModel
    case failedToCreateSynthesizer
    case generationFailed
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            return L10n.ttsErrorIncompleteModel
        case .failedToCreateSynthesizer:
            return L10n.ttsErrorLoadModel
        case .generationFailed:
            return L10n.ttsErrorGenerationFailed
        case .emptyAudio:
            return L10n.ttsErrorEmptyAudio
        }
    }
}

final class SherpaOnnxSynthesizer: @unchecked Sendable {
    private let synthesizer: OpaquePointer
    private let lock = NSLock()

    init(model: TtsModelKind, modelDirectory: URL) throws {
        let created: OpaquePointer?
        switch model {
        case .matchaChineseEnglish:
            created = try Self.createMatchaSynthesizer(modelDirectory: modelDirectory)
        case .kokoroMultilingualInt8:
            created = try Self.createKokoroSynthesizer(modelDirectory: modelDirectory)
        }

        guard let created else {
            throw SherpaOnnxSynthesizerError.failedToCreateSynthesizer
        }
        synthesizer = created
    }

    private static func createMatchaSynthesizer(modelDirectory: URL) throws -> OpaquePointer? {
        let modelURL = modelDirectory.appendingPathComponent("model-steps-3.onnx")
        let vocoderURL = modelDirectory.appendingPathComponent("vocos-16khz-univ.onnx")
        let tokensURL = modelDirectory.appendingPathComponent("tokens.txt")
        let dataDirectory = modelDirectory.appendingPathComponent("espeak-ng-data", isDirectory: true)
        let lexiconURL = modelDirectory.appendingPathComponent("lexicon.txt")
        let ruleURLs = ["date-zh.fst", "phone-zh.fst", "number-zh.fst"].map {
            modelDirectory.appendingPathComponent($0)
        }
        let requiredURLs = [
            modelURL,
            vocoderURL,
            tokensURL,
            dataDirectory,
            lexiconURL,
        ]
        guard requiredURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SherpaOnnxSynthesizerError.invalidModel
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.num_threads = Int32(max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4)))
        config.model.debug = 0
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        let ruleFSTs = ruleURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
            .joined(separator: ",")

        return modelURL.path.withCString { modelPath in
            vocoderURL.path.withCString { vocoderPath in
                tokensURL.path.withCString { tokensPath in
                    dataDirectory.path.withCString { dataPath in
                        lexiconURL.path.withCString { lexiconPath in
                            ruleFSTs.withCString { rulesPath in
                                "cpu".withCString { provider in
                                    config.model.provider = provider
                                    config.model.matcha.acoustic_model = modelPath
                                    config.model.matcha.vocoder = vocoderPath
                                    config.model.matcha.tokens = tokensPath
                                    config.model.matcha.data_dir = dataPath
                                    config.model.matcha.lexicon = lexiconPath
                                    config.rule_fsts = ruleFSTs.isEmpty ? nil : rulesPath
                                    return SherpaOnnxCreateOfflineTts(&config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func createKokoroSynthesizer(modelDirectory: URL) throws -> OpaquePointer? {
        let modelURL = modelDirectory.appendingPathComponent("model.int8.onnx")
        let voicesURL = modelDirectory.appendingPathComponent("voices.bin")
        let tokensURL = modelDirectory.appendingPathComponent("tokens.txt")
        let dataDirectory = modelDirectory.appendingPathComponent("espeak-ng-data", isDirectory: true)
        let englishLexiconURL = modelDirectory.appendingPathComponent("lexicon-us-en.txt")
        let chineseLexiconURL = modelDirectory.appendingPathComponent("lexicon-zh.txt")
        let ruleURLs = ["date-zh.fst", "phone-zh.fst", "number-zh.fst"].map {
            modelDirectory.appendingPathComponent($0)
        }
        let requiredURLs = [
            modelURL,
            voicesURL,
            tokensURL,
            dataDirectory,
            englishLexiconURL,
            chineseLexiconURL,
        ]
        guard requiredURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SherpaOnnxSynthesizerError.invalidModel
        }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.num_threads = Int32(max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4)))
        config.model.debug = 0
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        let lexicons = [englishLexiconURL.path, chineseLexiconURL.path].joined(separator: ",")
        let ruleFSTs = ruleURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
            .joined(separator: ",")

        return modelURL.path.withCString { modelPath in
            voicesURL.path.withCString { voicesPath in
                tokensURL.path.withCString { tokensPath in
                    dataDirectory.path.withCString { dataPath in
                        lexicons.withCString { lexiconPath in
                            ruleFSTs.withCString { rulesPath in
                                "cpu".withCString { provider in
                                    config.model.provider = provider
                                    config.model.kokoro.model = modelPath
                                    config.model.kokoro.voices = voicesPath
                                    config.model.kokoro.tokens = tokensPath
                                    config.model.kokoro.data_dir = dataPath
                                    config.model.kokoro.lexicon = lexiconPath
                                    config.rule_fsts = ruleFSTs.isEmpty ? nil : rulesPath
                                    return SherpaOnnxCreateOfflineTts(&config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(synthesizer)
    }

    func synthesize(
        text: String,
        voiceID: Int32,
        speed: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TtsAudioResult {
        let cancellation = TtsGenerationCancellation(progress: progress)
        return try await withTaskCancellationHandler {
            try lock.withLock {
                try Task.checkCancellation()

                var generationConfig = SherpaOnnxGenerationConfig()
                generationConfig.sid = voiceID
                generationConfig.speed = speed
                generationConfig.silence_scale = 0.2

                let opaqueContext = Unmanaged.passRetained(cancellation).toOpaque()
                defer { Unmanaged<TtsGenerationCancellation>.fromOpaque(opaqueContext).release() }

                let generated = text.withCString { textPointer in
                    SherpaOnnxOfflineTtsGenerateWithConfig(
                        synthesizer,
                        textPointer,
                        &generationConfig,
                        Self.progressCallback,
                        opaqueContext
                    )
                }
                guard let generated else {
                    if cancellation.isCancelled {
                        throw CancellationError()
                    }
                    throw SherpaOnnxSynthesizerError.generationFailed
                }
                defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(generated) }

                if cancellation.isCancelled {
                    throw CancellationError()
                }
                let audio = generated.pointee
                guard audio.n > 0, audio.sample_rate > 0, let samples = audio.samples else {
                    throw SherpaOnnxSynthesizerError.emptyAudio
                }
                return TtsAudioResult(
                    samples: Array(UnsafeBufferPointer(start: samples, count: Int(audio.n))),
                    sampleRate: Int(audio.sample_rate),
                    text: text,
                    voiceID: voiceID
                )
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static let progressCallback: @convention(c) (
        UnsafePointer<Float>?,
        Int32,
        Float,
        UnsafeMutableRawPointer?
    ) -> Int32 = { _, _, progress, context in
        guard let context else { return 0 }
        let cancellation = Unmanaged<TtsGenerationCancellation>
            .fromOpaque(context)
            .takeUnretainedValue()
        return cancellation.report(progress: Double(progress)) ? 1 : 0
    }
}

private final class TtsGenerationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (Double) -> Void
    private var cancelled = false

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
    }

    func report(progress: Double) -> Bool {
        guard !isCancelled else { return false }
        self.progress(min(max(progress, 0), 1))
        return !isCancelled
    }
}
