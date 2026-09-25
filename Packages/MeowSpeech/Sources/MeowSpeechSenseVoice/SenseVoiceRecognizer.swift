@preconcurrency import CoreML
import Accelerate
import Foundation
import MeowSpeechCore

/// CoreML SenseVoiceSmall recognizer extracted from FluidAudio's SenseVoice
/// pipeline. The actor owns all CoreML objects and exposes only MeowSpeechCore.
public actor SenseVoiceRecognizer: SpeechRecognizer {
    private let modelDirectory: URL
    private let layout: SenseVoiceModelLayout
    private let language: Int32
    private let textNorm: Int32
    private let computePolicy: SenseVoiceComputePolicy
    private var models: LoadedModels?

    public init(
        modelDirectory: URL,
        precision: SenseVoiceEncoderPrecision = .int8,
        language: Int32 = 0,
        textNorm: Int32 = 15,
        computePolicy: SenseVoiceComputePolicy = .automatic
    ) {
        self.modelDirectory = modelDirectory
        self.layout = SenseVoiceModelLayout(precision: precision)
        self.language = language
        self.textNorm = textNorm
        self.computePolicy = computePolicy
    }

    public func transcribe(
        samples: [Float],
        sampleRate: Double
    ) async throws -> TranscriptionResult {
        try Task.checkCancellation()
        guard sampleRate > 0, sampleRate == Double(SenseVoiceConstants.sampleRate) else {
            throw SpeechError.invalidAudio("SenseVoice requires 16 kHz mono audio.")
        }
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else {
            throw SpeechError.invalidAudio("The audio buffer is empty or invalid.")
        }

        let loadedModels = try loadModelsIfNeeded()
        let features = try runPreprocessor(samples, model: loadedModels.preprocessor)
        let (logits, validFrames) = try runEncoder(features, model: loadedModels.encoder)
        let rawText = decodeRaw(logits: logits, validFrames: validFrames, vocabulary: loadedModels.vocabulary)
        let parsed = parseTranscription(rawText)
        guard !parsed.text.isEmpty else {
            throw SpeechError.inferenceFailed("No speech was recognized.")
        }
        try Task.checkCancellation()
        return TranscriptionResult(
            text: parsed.text,
            language: parsed.language,
            duration: Double(samples.count) / sampleRate
        )
    }

    private func loadModelsIfNeeded() throws -> LoadedModels {
        if let models { return models }

        let preprocessorURL = modelDirectory.appendingPathComponent(layout.preprocessorPath)
        let encoderURL = modelDirectory.appendingPathComponent(layout.encoderPath)
        let vocabularyURL = modelDirectory.appendingPathComponent(layout.vocabularyPath)
        guard FileManager.default.fileExists(atPath: preprocessorURL.path),
              FileManager.default.fileExists(atPath: encoderURL.path),
              FileManager.default.fileExists(atPath: vocabularyURL.path)
        else {
            throw SpeechError.modelUnavailable
        }

        do {
            let preprocessorConfiguration = MLModelConfiguration()
            preprocessorConfiguration.computeUnits = .cpuOnly

            let encoderConfiguration = MLModelConfiguration()
            encoderConfiguration.computeUnits = computeUnits

            let loaded = LoadedModels(
                preprocessor: try loadModel(at: preprocessorURL, configuration: preprocessorConfiguration),
                encoder: try loadModel(at: encoderURL, configuration: encoderConfiguration),
                vocabulary: try loadVocabulary(at: vocabularyURL)
            )
            models = loaded
            return loaded
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.modelLoadFailed(error.localizedDescription)
        }
    }

    private var computeUnits: MLComputeUnits {
        switch computePolicy {
        case .automatic:
            return layout.precision == .fp32 ? .all : .cpuAndNeuralEngine
        case .cpuOnly:
            return .cpuOnly
        case .cpuAndNeuralEngine:
            return .cpuAndNeuralEngine
        case .all:
            return .all
        }
    }

    private func loadModel(at url: URL, configuration: MLModelConfiguration) throws -> MLModel {
        let modelURL: URL
        if url.pathExtension == "mlpackage" {
            modelURL = try MLModel.compileModel(at: url)
        } else {
            modelURL = url
        }
        return try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    private func loadVocabulary(at url: URL) throws -> [Int: String] {
        let data = try Data(contentsOf: url)
        if let array = try JSONSerialization.jsonObject(with: data) as? [String] {
            return Dictionary(uniqueKeysWithValues: array.enumerated().map { ($0.offset, $0.element) })
        }
        if let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: String] {
            return Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
                guard let index = Int(key) else { return nil }
                return (index, value)
            })
        }
        throw SpeechError.modelLoadFailed("SenseVoice vocabulary is not a JSON token list.")
    }

    private func runPreprocessor(_ samples: [Float], model: MLModel) throws -> MLMultiArray {
        let waveform = try MLMultiArray(
            shape: [1, NSNumber(value: samples.count)],
            dataType: .float32
        )
        let pointer = waveform.dataPointer.assumingMemoryBound(to: Float32.self)
        samples.withUnsafeBufferPointer { source in
            for index in source.indices {
                pointer[index] = source[index] * SenseVoiceConstants.waveformScale
            }
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "waveform": MLFeatureValue(multiArray: waveform)
        ])
        let output = try model.prediction(from: input)
        guard let features = output.featureValue(for: "features")?.multiArrayValue else {
            throw SpeechError.inferenceFailed("SenseVoice preprocessor produced no features.")
        }
        return features
    }

    private func runEncoder(
        _ features: MLMultiArray,
        model: MLModel
    ) throws -> (MLMultiArray, Int) {
        guard features.shape.count == 3 else {
            throw SpeechError.inferenceFailed("SenseVoice features have an unexpected shape.")
        }
        let featureCount = min(features.shape[1].intValue, SenseVoiceConstants.buckets.last ?? 1800)
        let bucket = SenseVoiceConstants.buckets.first(where: { $0 >= featureCount })
            ?? SenseVoiceConstants.buckets.last!
        let speech = try MLMultiArray(
            shape: [1, NSNumber(value: bucket), NSNumber(value: SenseVoiceConstants.featureDimension)],
            dataType: .float32
        )
        // CoreML does not guarantee newly allocated MLMultiArray storage is
        // zero-filled. The encoder receives a bucket larger than the valid
        // feature count for most recordings, so clear the padding explicitly
        // before copying the valid frames.
        let speechPointer = speech.dataPointer.assumingMemoryBound(to: Float32.self)
        memset(
            speechPointer,
            0,
            bucket * SenseVoiceConstants.featureDimension * MemoryLayout<Float32>.size
        )
        copyFeatures(features, into: speech, frameCount: featureCount)

        let lengths = try MLMultiArray(shape: [1], dataType: .int32)
        lengths[0] = NSNumber(value: featureCount)
        let language = try MLMultiArray(shape: [1], dataType: .int32)
        language[0] = NSNumber(value: self.language)
        let textNorm = try MLMultiArray(shape: [1], dataType: .int32)
        textNorm[0] = NSNumber(value: self.textNorm)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "speech": MLFeatureValue(multiArray: speech),
            "speech_lengths": MLFeatureValue(multiArray: lengths),
            "language": MLFeatureValue(multiArray: language),
            "textnorm": MLFeatureValue(multiArray: textNorm),
        ])
        let output = try model.prediction(from: input)
        guard let logits = output.featureValue(for: "ctc_logits")?.multiArrayValue else {
            throw SpeechError.inferenceFailed("SenseVoice encoder produced no CTC logits.")
        }
        return (logits, SenseVoiceConstants.queryTokenCount + featureCount)
    }

    private func copyFeatures(_ source: MLMultiArray, into destination: MLMultiArray, frameCount: Int) {
        let count = frameCount * SenseVoiceConstants.featureDimension
        let destinationPointer = destination.dataPointer.assumingMemoryBound(to: Float32.self)
        if source.dataType == .float32 {
            memcpy(destinationPointer, source.dataPointer, count * MemoryLayout<Float32>.size)
            return
        }
        for index in 0..<count {
            destinationPointer[index] = source[index].floatValue
        }
    }

    private func decodeRaw(
        logits: MLMultiArray,
        validFrames: Int,
        vocabulary: [Int: String]
    ) -> String {
        guard logits.shape.count == 3 else { return "" }
        let frames = min(validFrames, logits.shape[1].intValue)
        var tokenIDs: [Int] = []
        tokenIDs.reserveCapacity(frames)
        var previous = -1
        for tokenID in LogitsArgmax.argmaxPerFrame(logits: logits, frames: frames) {
            if tokenID != SenseVoiceConstants.blankID, tokenID != previous {
                tokenIDs.append(tokenID)
            }
            previous = tokenID
        }
        return decodeCtcTokenIDs(tokenIDs, vocabulary: vocabulary)
    }

    private func parseTranscription(_ raw: String) -> (text: String, language: String?) {
        let pattern = try? NSRegularExpression(pattern: "<\\|([^|]*)\\|>")
        let nsText = raw as NSString
        let matches = pattern?.matches(in: raw, range: NSRange(location: 0, length: nsText.length)) ?? []
        let tags = matches.map { nsText.substring(with: $0.range(at: 1)) }
        let cleaned = raw
            .replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let knownLanguages = Set(["zh", "en", "yue", "ja", "ko", "nospeech"])
        return (cleaned, tags.first(where: { knownLanguages.contains($0) }) ?? tags.first)
    }
}

private struct LoadedModels {
    let preprocessor: MLModel
    let encoder: MLModel
    let vocabulary: [Int: String]
}

private enum LogitsArgmax {
    static func argmaxPerFrame(logits: MLMultiArray, frames: Int) -> [Int] {
        let vocabularySize = logits.shape[2].intValue
        let frameStride = logits.strides[1].intValue
        var result: [Int] = []
        result.reserveCapacity(frames)

        if logits.dataType == .float32 {
            let pointer = logits.dataPointer.assumingMemoryBound(to: Float32.self)
            for frame in 0..<frames {
                var bestValue: Float = -.infinity
                var bestIndex: vDSP_Length = 0
                vDSP_maxvi(
                    pointer.advanced(by: frame * frameStride),
                    1,
                    &bestValue,
                    &bestIndex,
                    vDSP_Length(vocabularySize)
                )
                result.append(Int(bestIndex))
            }
        } else if logits.dataType == .float16 {
            let source = logits.dataPointer.assumingMemoryBound(to: UInt16.self)
            var values = [Float](repeating: 0, count: frames * frameStride)
            let valueCount = values.count
            values.withUnsafeMutableBufferPointer { destination in
                var sourceBuffer = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source),
                    height: 1,
                    width: vImagePixelCount(valueCount),
                    rowBytes: valueCount * MemoryLayout<UInt16>.stride
                )
                var destinationBuffer = vImage_Buffer(
                    data: destination.baseAddress!,
                    height: 1,
                    width: vImagePixelCount(valueCount),
                    rowBytes: valueCount * MemoryLayout<Float>.stride
                )
                vImageConvert_Planar16FtoPlanarF(&sourceBuffer, &destinationBuffer, 0)
            }
            for frame in 0..<frames {
                var bestValue: Float = -.infinity
                var bestIndex: vDSP_Length = 0
                vDSP_maxvi(
                    values.withUnsafeBufferPointer { $0.baseAddress!.advanced(by: frame * frameStride) },
                    1,
                    &bestValue,
                    &bestIndex,
                    vDSP_Length(vocabularySize)
                )
                result.append(Int(bestIndex))
            }
        } else {
            for frame in 0..<frames {
                var bestIndex = 0
                var bestValue = -Float.infinity
                for token in 0..<vocabularySize {
                    let value = logits[[0, frame, token] as [NSNumber]].floatValue
                    if value > bestValue {
                        bestValue = value
                        bestIndex = token
                    }
                }
                result.append(bestIndex)
            }
        }
        return result
    }
}

func decodeCtcTokenIDs(_ ids: [Int], vocabulary: [Int: String]) -> String {
    ids.compactMap { vocabulary[$0] }
        .joined()
        .replacingOccurrences(of: "▁", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
