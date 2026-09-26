import Foundation
import MeowSpeechCore

#if MEOW_VOICE
import MeowSpeechMossTTS
#endif

enum TtsModelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case system

    #if MEOW_VOICE
    case mossTTSNano = "mossTTSNano"
    #endif

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // `matchaChineseEnglish` was the former downloadable model setting. Keep
        // decoding it as the built-in voice backend so existing preferences
        // do not re-enable the removed runtime or trigger a model download.
        self = rawValue == "matchaChineseEnglish"
            ? .system
            : TtsModelKind(rawValue: rawValue) ?? .system
    }

    var displayName: String {
        switch self {
        case .system:
            return L10n.ttsModelSystemTitle
        #if MEOW_VOICE
        case .mossTTSNano:
            return L10n.ttsModelMossTitle
        #endif
        }
    }

    var description: String {
        switch self {
        case .system:
            return L10n.ttsModelSystemSubtitle
        #if MEOW_VOICE
        case .mossTTSNano:
            return L10n.ttsModelMossSubtitle
        #endif
        }
    }

    var licenseDescription: String {
        switch self {
        case .system:
            return L10n.ttsModelLicense
        #if MEOW_VOICE
        case .mossTTSNano:
            return L10n.ttsModelMossLicense
        #endif
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .system:
            return "system-voices"
        #if MEOW_VOICE
        case .mossTTSNano:
            return "moss-tts-nano-coreml"
        #endif
        }
    }

    #if MEOW_VOICE
    var manifest: SpeechModelManifest {
        let revision = "408475d01c46c9290b6546edf31e9cc5cbb202cd"
        let base = "https://huggingface.co/FluidInference/moss-tts-nano-coreml/resolve/\(revision)/"

        func artifact(
            _ path: String,
            sha256: String,
            byteCount: Int64
        ) -> SpeechModelArtifact {
            SpeechModelArtifact(
                id: "moss-\(path.replacingOccurrences(of: "/", with: "-"))",
                relativePath: path,
                remoteURL: URL(string: base + path)!,
                sha256: sha256,
                byteCount: byteCount
            )
        }

        let artifacts: [SpeechModelArtifact] = [
            artifact(
                "MossNano-Prefill-T512-M1024-fp16.mlmodelc/coremldata.bin",
                sha256: "c49c6c29764802ceb2b8e606277f9e11267391b1a20be1ed0477ba1096eb3843",
                byteCount: 447
            ),
            artifact(
                "MossNano-Prefill-T512-M1024-fp16.mlmodelc/model.mil",
                sha256: "54fa50c196d9af14fabefc8445129d0214e43025ba4f776f9bb8a48e00edbb9a",
                byteCount: 1_985_055
            ),
            artifact(
                "MossNano-Prefill-T512-M1024-fp16.mlmodelc/weights/weight.bin",
                sha256: "1ca31c05d0b9560ee4fc3aeb1bdb7c30e198384f3dfd11c2291b6628e9864381",
                byteCount: 221_595_648
            ),
            artifact(
                "MossNano-Step-M1024-fp16.mlmodelc/coremldata.bin",
                sha256: "1d83ec892dc533c5e6fda3133a2e2672e4ee07de9899085a4f4e046bc0945349",
                byteCount: 500
            ),
            artifact(
                "MossNano-Step-M1024-fp16.mlmodelc/model.mil",
                sha256: "d7a8732ea51b41326de20cd4c5a2b0036f036aeac42bd53ab76da7796f3c9c71",
                byteCount: 313_443
            ),
            artifact(
                "MossNano-Step-M1024-fp16.mlmodelc/weights/weight.bin",
                sha256: "51bad5eb40692ec9d99970e708a28115a1ab5d211f14078a1f7fb0d46ead5838",
                byteCount: 220_420_096
            ),
            artifact(
                "MossNano-Frame-fp16.mlmodelc/coremldata.bin",
                sha256: "0f8b1f54ce0fa82e8c28bdcab7650d71bf0a82e870f1ea429846635dbd7c7640",
                byteCount: 615
            ),
            artifact(
                "MossNano-Frame-fp16.mlmodelc/model.mil",
                sha256: "a44db104233418472c11dbc3b1f55fb6631c4f53341f1b6f0db79f7d075bf36b",
                byteCount: 592_083
            ),
            artifact(
                "MossNano-Frame-fp16.mlmodelc/weights/weight.bin",
                sha256: "63018ed6ab5973174ccedbdd5570fb80b4900916d3e0c58515f2b82a901bb750",
                byteCount: 64_560_640
            ),
            artifact(
                "MossNano-CodecStep-fp16.mlmodelc/coremldata.bin",
                sha256: "d0db0a83e4a79c1b8c831b158b25632510c29f653e72d2b2f6101e4e50b8ace1",
                byteCount: 1_596
            ),
            artifact(
                "MossNano-CodecStep-fp16.mlmodelc/model.mil",
                sha256: "9cc2a7a1a11ce7ed59b407861725b8bee27fbae95a2b7c88df875610dd92222d",
                byteCount: 854_244
            ),
            artifact(
                "MossNano-CodecStep-fp16.mlmodelc/weights/weight.bin",
                sha256: "22e936dff9dee44c64b1a9d7746543ecbc92bdd2946c59c608674a5a1a4c35d4",
                byteCount: 22_973_536
            ),
            artifact(
                "MossNano-CodecDecoder-fp16.mlmodelc/coremldata.bin",
                sha256: "616fe22083acb1be699d7ef9e91ff2ebf2a9af5a45facfeffa027c3753b47fcf",
                byteCount: 385
            ),
            artifact(
                "MossNano-CodecDecoder-fp16.mlmodelc/model.mil",
                sha256: "dddea7d421b084812a4208dfab66820facd84ab394b74ffcf006064c3115bb09",
                byteCount: 451_882
            ),
            artifact(
                "MossNano-CodecDecoder-fp16.mlmodelc/weights/weight.bin",
                sha256: "88976cf052fd509eb9aae8b6cb03abe3a0cfe9ba4e40ea6ffbd0ac6e98a51dfc",
                byteCount: 22_117_280
            ),
            artifact(
                "MossNano-CodecEncoder-fp32.mlmodelc/coremldata.bin",
                sha256: "88b5a8140ab1b52ddc32a1bfa3b72bcdb61198592ee82cba400d77218c372076",
                byteCount: 390
            ),
            artifact(
                "MossNano-CodecEncoder-fp32.mlmodelc/model.mil",
                sha256: "360e7c2e345a260d89b18ec94335ba0151232e2bcf744f9e55e7f4ee78625800",
                byteCount: 467_527
            ),
            artifact(
                "MossNano-CodecEncoder-fp32.mlmodelc/weights/weight.bin",
                sha256: "4198fdb9675bc8ff4318c35434203f05b75adca4e6c947a8bc32d8957fe48e00",
                byteCount: 44_959_552
            ),
            artifact(
                "config.json",
                sha256: "fcee7b9bcaf5d832a18523aec3f11073d791fd8839e83ce60a50d7f50e781834",
                byteCount: 3_109
            ),
            artifact(
                "tokenizer.model",
                sha256: "c353ee1479b536bf414c1b247f5542b6607fb8ae91320e5af1781fee200fddff",
                byteCount: 470_897
            ),
            artifact(
                "voices/en_2.json",
                sha256: "80726daf4580a4a8d4568fcd2a532f5557e88aaefc13c4c9faf8172cf1e560d6",
                byteCount: 7_953
            ),
            artifact(
                "voices/zh_1.json",
                sha256: "a057c84ef1fcb7410ee795313de0819363cd396ea1eb92140e15fa8ff5c4bbad",
                byteCount: 7_967
            ),
        ]
        return SpeechModelManifest(
            id: "moss-tts-nano-coreml",
            version: revision,
            backend: "moss-tts-nano-coreml",
            artifacts: artifacts
        )
    }
    #endif

    var requiredRelativePaths: [String] {
        #if MEOW_VOICE
        switch self {
        case .system:
            return []
        case .mossTTSNano:
            return manifest.requiredRelativePaths
        }
        #else
        return []
        #endif
    }
}

struct TtsSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var model: TtsModelKind
    var voiceID: Int32
    var speed: Double
    var autoPlay: Bool
    var exportDirectory: String

    static let `default` = TtsSettings(
        enabled: false,
        model: .system,
        voiceID: 0,
        speed: 1,
        autoPlay: true,
        exportDirectory: ""
    )
}

extension TtsSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case model
        case voiceID
        case speed
        case autoPlay
        case exportDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        model = try container.decodeIfPresent(TtsModelKind.self, forKey: .model) ?? Self.default.model
        voiceID = try container.decodeIfPresent(Int32.self, forKey: .voiceID) ?? Self.default.voiceID
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? Self.default.speed
        autoPlay = try container.decodeIfPresent(Bool.self, forKey: .autoPlay) ?? Self.default.autoPlay
        exportDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .exportDirectory
        ) ?? Self.default.exportDirectory

        self = normalized()
    }

    func normalized() -> TtsSettings {
        var copy = self
        copy.speed = 1
        copy.autoPlay = true
        copy.voiceID = 0
        return copy
    }
}

struct TtsAudioResult: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let text: String
    let voiceID: Int32

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRate)
    }
}

enum TtsSynthesisState: Equatable, Sendable {
    case idle
    case needsModel
    case loadingModel
    case synthesizing(Double)
    case ready
    case playing
    case paused
    case failed(String)

    var isGenerating: Bool {
        switch self {
        case .loadingModel, .synthesizing:
            return true
        default:
            return false
        }
    }
}
