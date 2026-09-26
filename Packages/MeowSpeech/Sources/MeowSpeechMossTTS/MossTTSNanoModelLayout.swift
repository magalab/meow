@preconcurrency import CoreML
import Foundation

/// Compute-unit policies used by the MOSS-TTS-Nano CoreML graphs.
public enum MossTTSNanoComputePolicy: String, CaseIterable, Sendable {
    case automatic
    case cpuOnly
    case cpuAndNeuralEngine
    case cpuAndGPU
    case all

    var computeUnits: MLComputeUnits {
        switch self {
        case .automatic:
            return .all
        case .cpuOnly:
            return .cpuOnly
        case .cpuAndNeuralEngine:
            return .cpuAndNeuralEngine
        case .cpuAndGPU:
            return .cpuAndGPU
        case .all:
            return .all
        }
    }
}

/// Files shipped by the `FluidInference/moss-tts-nano-coreml` model revision.
///
/// The model repository contains precompiled `.mlmodelc` bundles. Keeping the
/// names here, instead of scattering them across the inference loop, makes the
/// model downloader and the CoreML loader share one source of truth.
public struct MossTTSNanoModelLayout: Sendable, Equatable {
    public let prefillModelName: String
    public let stepModelName: String
    public let frameModelName: String
    public let codecStepModelName: String
    public let codecDecoderModelName: String
    public let codecEncoderModelName: String
    public let configPath: String
    public let tokenizerPath: String
    public let presetVoicePaths: [String]

    public init(
        prefillModelName: String = "MossNano-Prefill-T512-M1024-fp16.mlmodelc",
        stepModelName: String = "MossNano-Step-M1024-fp16.mlmodelc",
        frameModelName: String = "MossNano-Frame-fp16.mlmodelc",
        codecStepModelName: String = "MossNano-CodecStep-fp16.mlmodelc",
        codecDecoderModelName: String = "MossNano-CodecDecoder-fp16.mlmodelc",
        codecEncoderModelName: String = "MossNano-CodecEncoder-fp32.mlmodelc",
        configPath: String = "config.json",
        tokenizerPath: String = "tokenizer.model",
        presetVoicePaths: [String] = ["voices/en_2.json", "voices/zh_1.json"]
    ) {
        self.prefillModelName = prefillModelName
        self.stepModelName = stepModelName
        self.frameModelName = frameModelName
        self.codecStepModelName = codecStepModelName
        self.codecDecoderModelName = codecDecoderModelName
        self.codecEncoderModelName = codecEncoderModelName
        self.configPath = configPath
        self.tokenizerPath = tokenizerPath
        self.presetVoicePaths = presetVoicePaths
    }

    public static let current = MossTTSNanoModelLayout()

    public var modelNames: [String] {
        [
            prefillModelName,
            stepModelName,
            frameModelName,
            codecStepModelName,
            codecDecoderModelName,
            codecEncoderModelName,
        ]
    }

    /// Required for model loading. Preset voices remain optional so voice
    /// cloning can be enabled independently of the built-in voice library.
    public var requiredRelativePaths: [String] {
        modelNames + [configPath, tokenizerPath]
    }

    public var optionalRelativePaths: [String] {
        presetVoicePaths
    }

    /// Individual files needed when this layout is installed from a remote
    /// model repository. CoreML treats each `.mlmodelc` directory as a bundle,
    /// so a downloader must materialize these files rather than only creating
    /// the directory names.
    public var installRelativePaths: [String] {
        let compiledModelFiles = modelNames.flatMap { name in
            [
                "\(name)/coremldata.bin",
                "\(name)/model.mil",
                "\(name)/weights/weight.bin",
            ]
        }
        return compiledModelFiles + [configPath, tokenizerPath] + presetVoicePaths
    }

    public func modelURL(in directory: URL, named name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: true)
    }

    public func requiredFilesExist(in directory: URL, fileManager: FileManager = .default) -> Bool {
        requiredRelativePaths.allSatisfy { relativePath in
            fileManager.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }
}
