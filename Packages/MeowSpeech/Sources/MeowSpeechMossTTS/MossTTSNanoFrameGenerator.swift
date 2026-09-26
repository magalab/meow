@preconcurrency import CoreML
import Foundation
import MeowSpeechCore

public struct MossTTSNanoFrame: Sendable, Equatable {
    public let codebookTokens: [Int32]
    public let isFinal: Bool

    public init(codebookTokens: [Int32], isFinal: Bool = false) {
        self.codebookTokens = codebookTokens
        self.isFinal = isFinal
    }
}

/// CoreML prefill → frame sampling → autoregressive step loop.
///
/// The graph performs text/audio sampling internally. Swift only supplies the
/// prompt, KV state, sampling controls, random uniforms, and repetition mask.
public extension MossTTSNanoModelLoader {
    func generateFrames(
        for prompt: MossTTSNanoPrompt,
        maxFrames: Int = 375,
        greedy: Bool = false,
        seed: UInt64 = 0x4D_4F_53_53
    ) throws -> [MossTTSNanoFrame] {
        try generateFramesInternal(
            for: prompt,
            maxFrames: maxFrames,
            greedy: greedy,
            seed: seed,
            onFrame: nil
        )
    }

    /// Generates and decodes audio in bounded batches instead of retaining
    /// every generated frame until the utterance is complete. This keeps the
    /// first playable audio close to the first few autoregressive frames.
    @discardableResult
    func generateAudio(
        for prompt: MossTTSNanoPrompt,
        maxFrames: Int = 375,
        greedy: Bool = false,
        seed: UInt64 = 0x4D_4F_53_53,
        maximumFramesPerCall: Int = 4,
        onAudio: @escaping @Sendable (MossTTSNanoAudio) -> Void
    ) throws -> Int {
        guard maximumFramesPerCall > 0 else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano decoder frame limit must be positive.")
        }

        var pendingFrames: [MossTTSNanoFrame] = []
        pendingFrames.reserveCapacity(maximumFramesPerCall)
        var emittedFrameCount = 0

        _ = try generateFramesInternal(
            for: prompt,
            maxFrames: maxFrames,
            greedy: greedy,
            seed: seed
        ) { frame in
            guard !frame.codebookTokens.isEmpty else { return }
            pendingFrames.append(frame)
            guard pendingFrames.count >= maximumFramesPerCall else { return }

            let audio = try self.decodeAudio(
                from: pendingFrames,
                maximumFramesPerCall: pendingFrames.count
            )
            emittedFrameCount += pendingFrames.count
            pendingFrames.removeAll(keepingCapacity: true)
            onAudio(audio)
        }

        if !pendingFrames.isEmpty {
            let audio = try decodeAudio(
                from: pendingFrames,
                maximumFramesPerCall: pendingFrames.count
            )
            emittedFrameCount += pendingFrames.count
            onAudio(audio)
        }
        return emittedFrameCount
    }

    private func generateFramesInternal(
        for prompt: MossTTSNanoPrompt,
        maxFrames: Int,
        greedy: Bool,
        seed: UInt64,
        onFrame: ((MossTTSNanoFrame) throws -> Void)?
    ) throws -> [MossTTSNanoFrame] {
        try prepare()
        guard let configuration = loadedConfiguration else {
            throw SpeechError.modelUnavailable
        }
        guard prompt.rows.count == configuration.maxPrefillRows,
              prompt.rows.allSatisfy({ $0.count == configuration.nVQ + 1 }),
              prompt.inputLength > 0,
              prompt.inputLength <= configuration.maxPrefillRows
        else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano prompt shape is invalid.")
        }
        guard maxFrames > 0 else { return [] }

        let prefill = try model(named: layout.prefillModelName)
        let step = try model(named: layout.stepModelName)
        let frame = try model(named: layout.frameModelName)

        var globalHidden: MLMultiArray
        var keyCache: MLMultiArray
        var valueCache: MLMultiArray
        do {
            let inputIDs = try int32Array(
                shape: [1, configuration.maxPrefillRows, configuration.nVQ + 1],
                values: prompt.rows.flatMap { $0 }
            )
            let inputLength = try int32Array(shape: [1], values: [Int32(prompt.inputLength)])
            let output = try prefill.prediction(from: try provider([
                "input_ids": inputIDs,
                "input_len": inputLength,
            ]))
            globalHidden = try outputArray(output, named: "hidden")
            keyCache = try outputArray(output, named: "kv_k")
            valueCache = try outputArray(output, named: "kv_v")
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.inferenceFailed(
                "MOSS-TTS-Nano prefill failed: \(error.localizedDescription)"
            )
        }

        var currentLength = prompt.inputLength
        let seen = try int32Array(
            shape: [1, configuration.nVQ, configuration.audioCodebookSizes[0]],
            values: Array(repeating: 0, count: configuration.nVQ * configuration.audioCodebookSizes[0])
        )
        var random = MossTTSNanoRandomSource(seed: seed)
        var generated: [MossTTSNanoFrame] = []
        generated.reserveCapacity(maxFrames)

        for _ in 0..<maxFrames {
            try Task.checkCancellation()
            let frameOutput: MLFeatureProvider
            do {
                frameOutput = try frame.prediction(from: try provider([
                    "global_hidden": globalHidden,
                    "text_u": try floatArray(shape: [1], values: [random.nextUnit()]),
                    "audio_u": try floatArray(
                        shape: [1, configuration.nVQ],
                        values: (0..<configuration.nVQ).map { _ in random.nextUnit() }
                    ),
                    "text_temperature": try floatArray(
                        shape: [1],
                        values: [configuration.sampling.textTemperature]
                    ),
                    "audio_temperature": try floatArray(
                        shape: [1],
                        values: [configuration.sampling.audioTemperature]
                    ),
                    "audio_top_p": try floatArray(
                        shape: [1],
                        values: [configuration.sampling.audioTopP]
                    ),
                    "repetition_penalty": try floatArray(
                        shape: [1],
                        values: [configuration.sampling.audioRepetitionPenalty]
                    ),
                    "seen": seen,
                    "greedy": int32Array(shape: [1], values: [greedy ? 1 : 0]),
                ]))
            } catch {
                throw SpeechError.inferenceFailed(
                    "MOSS-TTS-Nano frame generation failed: \(error.localizedDescription)"
                )
            }

            let shouldContinue = try scalarInt(
                outputArray(frameOutput, named: "should_continue")
            ) != 0
            let tokens = try integerVector(
                outputArray(frameOutput, named: "frame"),
                count: configuration.nVQ
            )
            guard shouldContinue else {
                let finalFrame = MossTTSNanoFrame(codebookTokens: [], isFinal: true)
                generated.append(finalFrame)
                try onFrame?(finalFrame)
                break
            }
            guard tokens.count == configuration.nVQ else {
                throw SpeechError.inferenceFailed("MOSS-TTS-Nano returned an invalid audio frame.")
            }

            let frame = MossTTSNanoFrame(codebookTokens: tokens)
            generated.append(frame)
            try onFrame?(frame)
            for (channel, token) in tokens.enumerated()
            where channel < configuration.nVQ
                && token >= 0
                && token < configuration.audioCodebookSizes[channel]
            {
                seen[[0, channel, Int(token)] as [NSNumber]] = 1
            }

            let nextRow = [configuration.audioAssistantSlotTokenID]
                + tokens
                + Array(
                    repeating: configuration.audioPadTokenID,
                    count: max(0, configuration.nVQ - tokens.count)
                )
            do {
                let output = try step.prediction(from: try provider([
                    "input_ids": try int32Array(
                        shape: [1, 1, configuration.nVQ + 1],
                        values: nextRow
                    ),
                    "kv_k": keyCache,
                    "kv_v": valueCache,
                    "cur_len": try int32Array(shape: [1], values: [Int32(currentLength)]),
                ]))
                globalHidden = try outputArray(output, named: "hidden")
                keyCache = try outputArray(output, named: "kv_k_out")
                valueCache = try outputArray(output, named: "kv_v_out")
            } catch {
                throw SpeechError.inferenceFailed(
                    "MOSS-TTS-Nano autoregressive step failed: \(error.localizedDescription)"
                )
            }
            currentLength += 1
        }
        return generated
    }

    private func model(named name: String) throws -> MLModel {
        guard let model = loadedModels[name] else {
            throw SpeechError.modelUnavailable
        }
        return model
    }

    func decodeAudio(
        from frames: [MossTTSNanoFrame],
        maximumFramesPerCall: Int = 125
    ) throws -> MossTTSNanoAudio {
        try prepare()
        guard let configuration = loadedConfiguration else {
            throw SpeechError.modelUnavailable
        }
        let audioFrames = frames
            .filter { !$0.codebookTokens.isEmpty }
            .map(\.codebookTokens)
        guard !audioFrames.isEmpty else {
            return MossTTSNanoAudio(channels: [[], []], sampleRate: configuration.sampleRate)
        }
        guard maximumFramesPerCall > 0 else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano decoder frame limit must be positive.")
        }

        let decoder = try model(named: layout.codecDecoderModelName)
        var channels = [[], []] as [[Float]]
        for start in stride(from: 0, to: audioFrames.count, by: maximumFramesPerCall) {
            let end = min(start + maximumFramesPerCall, audioFrames.count)
            let batch = Array(audioFrames[start..<end])
            let frameCount = batch.count
            let values = (0..<configuration.nVQ).flatMap { channel in
                batch.map { frame in
                    frame.indices.contains(channel) ? frame[channel] : configuration.audioPadTokenID
                }
            }
            let codes = try int32Array(
                shape: [configuration.nVQ, 1, frameCount],
                values: values
            )
            do {
                let output = try decoder.prediction(from: try provider(["codes": codes]))
                let audio = try outputArray(output, named: "audio")
                let decoded = try audioChannels(from: audio)
                guard decoded.count == 2 else {
                    throw SpeechError.inferenceFailed(
                        "MOSS-TTS-Nano codec returned \(decoded.count) channels."
                    )
                }
                channels[0].append(contentsOf: decoded[0])
                channels[1].append(contentsOf: decoded[1])
            } catch let error as SpeechError {
                throw error
            } catch {
                throw SpeechError.inferenceFailed(
                    "MOSS-TTS-Nano codec decoding failed: \(error.localizedDescription)"
                )
            }
        }
        return MossTTSNanoAudio(channels: channels, sampleRate: configuration.sampleRate)
    }
}

private extension MossTTSNanoModelLoader {
    func provider(_ arrays: [String: MLMultiArray]) throws -> MLDictionaryFeatureProvider {
        try MLDictionaryFeatureProvider(
            dictionary: arrays.mapValues { MLFeatureValue(multiArray: $0) }
        )
    }

    func outputArray(_ provider: MLFeatureProvider, named name: String) throws -> MLMultiArray {
        guard let array = provider.featureValue(for: name)?.multiArrayValue else {
            throw SpeechError.inferenceFailed("MOSS-TTS-Nano graph output is missing: \(name).")
        }
        return array
    }

    func int32Array(shape: [Int], values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: shape.map { NSNumber(value: $0) },
            dataType: .int32
        )
        guard array.count == values.count else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano tensor shape does not match its values.")
        }
        for index in values.indices {
            array[index] = NSNumber(value: values[index])
        }
        return array
    }

    func floatArray(shape: [Int], values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(
            shape: shape.map { NSNumber(value: $0) },
            dataType: .float32
        )
        guard array.count == values.count else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano tensor shape does not match its values.")
        }
        for index in values.indices {
            array[index] = NSNumber(value: values[index])
        }
        return array
    }

    func scalarInt(_ array: MLMultiArray) throws -> Int {
        guard array.count > 0 else {
            throw SpeechError.inferenceFailed("MOSS-TTS-Nano returned an empty scalar.")
        }
        return array[0].intValue
    }

    func integerVector(_ array: MLMultiArray, count: Int) throws -> [Int32] {
        guard array.count >= count else {
            throw SpeechError.inferenceFailed("MOSS-TTS-Nano returned a short audio frame.")
        }
        return (0..<count).map { Int32(array[$0].intValue) }
    }

    func audioChannels(from array: MLMultiArray) throws -> [[Float]] {
        let shape = array.shape.map(\.intValue)
        guard shape.count == 3, shape[0] == 1, shape[1] > 0, shape[2] > 0 else {
            throw SpeechError.inferenceFailed("MOSS-TTS-Nano codec returned an invalid audio shape.")
        }
        let channelCount = shape[1]
        let sampleCount = shape[2]
        var channels = Array(
            repeating: [Float](),
            count: channelCount
        )
        for channel in 0..<channelCount {
            channels[channel] = (0..<sampleCount).map { sampleIndex in
                let flatIndex = channel * sampleCount + sampleIndex
                return array[flatIndex].floatValue
            }
        }
        return channels
    }
}

private struct MossTTSNanoRandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUnit() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Float(Double(value >> 40) / Double(1 << 24))
    }
}

public struct MossTTSNanoAudio: Sendable, Equatable {
    public let channels: [[Float]]
    public let sampleRate: Int

    public init(channels: [[Float]], sampleRate: Int) {
        self.channels = channels
        self.sampleRate = sampleRate
    }

    public var channelCount: Int {
        channels.count
    }

    public var frameCount: Int {
        channels.map(\.count).min() ?? 0
    }
}
