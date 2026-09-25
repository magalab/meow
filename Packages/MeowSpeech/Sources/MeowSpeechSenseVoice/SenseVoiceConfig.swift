import Foundation

public enum SenseVoiceEncoderPrecision: String, Sendable, CaseIterable {
    case fp16
    case int8
    case fp32

    var modelName: String {
        switch self {
        case .fp16: return "SenseVoiceSmall"
        case .int8: return "SenseVoiceSmall_int8"
        case .fp32: return "SenseVoiceSmall_fp32"
        }
    }
}

public enum SenseVoiceComputePolicy: String, Sendable, CaseIterable {
    case automatic
    case cpuOnly
    case cpuAndNeuralEngine
    case all
}

public struct SenseVoiceModelLayout: Sendable, Equatable {
    public let precision: SenseVoiceEncoderPrecision

    public init(precision: SenseVoiceEncoderPrecision = .int8) {
        self.precision = precision
    }

    public var preprocessorPath: String {
        "SenseVoicePreprocessor.mlmodelc"
    }

    public var encoderPath: String {
        "\(precision.modelName).mlmodelc"
    }

    public var vocabularyPath: String {
        "vocab.json"
    }

    public var requiredRelativePaths: [String] {
        [
            "\(preprocessorPath)/coremldata.bin",
            "\(preprocessorPath)/model.mil",
            "\(preprocessorPath)/weights/weight.bin",
            "\(encoderPath)/coremldata.bin",
            "\(encoderPath)/model.mil",
            "\(encoderPath)/weights/weight.bin",
            vocabularyPath,
        ]
    }
}

enum SenseVoiceConstants {
    static let sampleRate = 16_000
    static let featureDimension = 560
    static let buckets = [128, 256, 512, 1024, 1800]
    static let queryTokenCount = 4
    static let blankID = 0
    static let waveformScale: Float = 32_768
    static let defaultLanguage: Int32 = 0
    static let defaultTextNorm: Int32 = 15
}
