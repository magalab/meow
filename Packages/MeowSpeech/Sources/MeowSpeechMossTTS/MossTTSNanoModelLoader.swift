@preconcurrency import CoreML
import Foundation
import MeowSpeechCore

/// Loads and retains the MOSS-TTS-Nano CoreML graph set.
///
/// This is deliberately a separate actor from the synthesizer. Model loading
/// is expensive and must be serialized, while inference needs its own
/// cancellation and streaming lifecycle.
public actor MossTTSNanoModelLoader {
    public let modelDirectory: URL
    public let layout: MossTTSNanoModelLayout
    public let computePolicy: MossTTSNanoComputePolicy

    var loadedModels: [String: MLModel] = [:]
    var loadedConfiguration: MossTTSNanoConfig?
    var loadedTokenizer: MossTTSNanoTokenizer?
    var isWarmingInference = false
    var didWarmInference = false

    public init(
        modelDirectory: URL,
        layout: MossTTSNanoModelLayout = .current,
        computePolicy: MossTTSNanoComputePolicy = .cpuAndGPU
    ) {
        self.modelDirectory = modelDirectory
        self.layout = layout
        self.computePolicy = computePolicy
    }

    public var isReady: Bool {
        loadedModels.count == layout.modelNames.count
            && loadedConfiguration != nil
            && loadedTokenizer != nil
    }

    /// Compiles, if needed, and loads every graph required by the streaming
    /// pipeline. The operation is idempotent after a successful load.
    public func prepare() throws {
        guard layout.requiredFilesExist(in: modelDirectory) else {
            throw SpeechError.modelUnavailable
        }
        guard !isReady else { return }

        do {
            var models: [String: MLModel] = [:]
            models.reserveCapacity(layout.modelNames.count)
            for name in layout.modelNames {
                let url = modelDirectory.appendingPathComponent(name, isDirectory: true)
                models[name] = try Self.loadModel(at: url, computePolicy: computePolicy)
            }
            let configurationData = try Data(
                contentsOf: modelDirectory.appendingPathComponent(layout.configPath)
            )
            let tokenizerData = try Data(
                contentsOf: modelDirectory.appendingPathComponent(layout.tokenizerPath)
            )
            let configuration = try MossTTSNanoConfig(data: configurationData)
            let tokenizer = try MossTTSNanoTokenizer(modelData: tokenizerData)
            loadedModels = models
            loadedConfiguration = configuration
            loadedTokenizer = tokenizer
        } catch let error as SpeechError {
            throw error
        } catch {
            loadedModels.removeAll(keepingCapacity: false)
            loadedConfiguration = nil
            loadedTokenizer = nil
            throw SpeechError.modelLoadFailed(error.localizedDescription)
        }
    }

    public func unload() {
        loadedModels.removeAll(keepingCapacity: false)
        loadedConfiguration = nil
        loadedTokenizer = nil
        isWarmingInference = false
        didWarmInference = false
    }

    func beginInferenceWarmup() -> Bool {
        guard !didWarmInference, !isWarmingInference else { return false }
        isWarmingInference = true
        return true
    }

    func finishInferenceWarmup(success: Bool) {
        isWarmingInference = false
        didWarmInference = success
    }

    public func configuration() throws -> MossTTSNanoConfig {
        guard let loadedConfiguration else {
            throw SpeechError.modelUnavailable
        }
        return loadedConfiguration
    }

    public func tokenize(_ text: String) throws -> [Int32] {
        guard let loadedTokenizer else {
            throw SpeechError.modelUnavailable
        }
        return loadedTokenizer.encode(text)
    }

    public func presetVoiceIDs() -> [String] {
        layout.presetVoicePaths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension == "json" else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    public func presetVoiceCodes(for voiceID: String) throws -> [[Int32]] {
        let normalizedID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty,
              normalizedID.unicodeScalars.allSatisfy({
                  let value = $0.value
                  return (value >= 48 && value <= 57)
                      || (value >= 65 && value <= 90)
                      || (value >= 97 && value <= 122)
                      || value == 95
                      || value == 45
              })
        else {
            throw SpeechError.invalidAudio("MOSS-TTS-Nano voice ID is invalid.")
        }

        let relativePath = layout.presetVoicePaths.first { path in
            URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent == normalizedID
        } ?? "voices/\(normalizedID).json"
        let url = modelDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpeechError.modelUnavailable
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            if let rows = try? decoder.decode([[Int32]].self, from: data) {
                return rows
            }
            let document = try decoder.decode(MossTTSNanoPresetVoiceDocument.self, from: data)
            return document.codes
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.modelLoadFailed(
                "MOSS-TTS-Nano preset voice could not be decoded: \(error.localizedDescription)"
            )
        }
    }

    private static func loadModel(
        at url: URL,
        computePolicy: MossTTSNanoComputePolicy
    ) throws -> MLModel {
        let compiledURL: URL
        if url.pathExtension == "mlpackage" {
            compiledURL = try MLModel.compileModel(at: url)
        } else {
            compiledURL = url
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computePolicy.computeUnits
        return try MLModel(contentsOf: compiledURL, configuration: configuration)
    }
}

private struct MossTTSNanoPresetVoiceDocument: Decodable {
    let codes: [[Int32]]

    private enum CodingKeys: String, CodingKey {
        case codes
        case promptAudioCodes = "prompt_audio_codes"
        case audioCodes = "audio_codes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codes = try container.decodeIfPresent([[Int32]].self, forKey: .codes)
            ?? container.decodeIfPresent([[Int32]].self, forKey: .promptAudioCodes)
            ?? container.decode([[Int32]].self, forKey: .audioCodes)
    }
}
