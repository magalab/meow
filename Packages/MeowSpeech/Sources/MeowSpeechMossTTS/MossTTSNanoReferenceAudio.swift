@preconcurrency import CoreML
import Foundation
import MeowSpeechCore

/// Encodes a 48 kHz stereo reference clip into the RVQ rows consumed by the
/// MOSS prompt builder. The CoreML encoder accepts at most 188 80-ms frames.
public extension MossTTSNanoModelLoader {
    func encodeReferenceAudio(_ audio: MossTTSNanoAudio) throws -> [[Int32]] {
        try prepare()
        guard let configuration = loadedConfiguration else {
            throw SpeechError.modelUnavailable
        }
        guard audio.sampleRate == configuration.sampleRate else {
            throw SpeechError.invalidAudio(
                "MOSS-TTS-Nano reference audio must be sampled at \(configuration.sampleRate) Hz."
            )
        }
        guard audio.channelCount == 2,
              audio.channels.allSatisfy({ $0.count == audio.frameCount }),
              audio.frameCount > 0,
              audio.frameCount.isMultiple(of: 3_840)
        else {
            throw SpeechError.invalidAudio(
                "MOSS-TTS-Nano reference audio must be non-empty, stereo, and aligned to 80 ms frames."
            )
        }
        let frameCount = audio.frameCount / 3_840
        guard frameCount <= 188 else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano reference audio is longer than 15 seconds.")
        }
        guard let encoder = loadedModels[layout.codecEncoderModelName] else {
            throw SpeechError.modelUnavailable
        }

        do {
            let input = try floatArray(
                shape: [1, 2, audio.frameCount],
                values: audio.channels[0] + audio.channels[1]
            )
            let output = try encoder.prediction(
                from: MLDictionaryFeatureProvider(dictionary: [
                    "audio": MLFeatureValue(multiArray: input),
                ])
            )
            guard let codes = output.featureValue(for: "codes")?.multiArrayValue else {
                throw SpeechError.inferenceFailed("MOSS-TTS-Nano encoder output is missing: codes.")
            }
            let shape = codes.shape.map(\.intValue)
            guard shape.count == 3,
                  shape[0] == configuration.nVQ,
                  shape[1] == 1,
                  shape[2] == frameCount
            else {
                throw SpeechError.inferenceFailed("MOSS-TTS-Nano encoder returned an invalid code shape.")
            }
            return (0..<frameCount).map { frameIndex in
                (0..<configuration.nVQ).map { channel in
                    codes[channel * frameCount + frameIndex].int32Value
                }
            }
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.inferenceFailed(
                "MOSS-TTS-Nano reference audio encoding failed: \(error.localizedDescription)"
            )
        }
    }
}

private extension MossTTSNanoModelLoader {
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
}
