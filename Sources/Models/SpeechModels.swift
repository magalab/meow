import Foundation
import MeowSpeechCore

enum SpeechModelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case senseVoice = "senseVoice"

    var id: String { rawValue }

    var displayName: String {
        L10n.speechModelSenseVoiceTitle
    }

    var description: String {
        L10n.speechModelSenseVoiceSubtitle
    }

    var downloadConfirmTitle: String {
        L10n.speechModelSenseVoiceDownloadConfirmTitle
    }

    var downloadConfirmMessage: String {
        L10n.speechModelSenseVoiceDownloadConfirmMessage
    }

    var storageDirectoryName: String {
        "sensevoice-small-coreml-int8"
    }

    /// Pinned to the model repository revision used by the extracted
    /// MeowSpeech SenseVoice backend. The model files are intentionally kept
    /// out of the app bundle and downloaded into Application Support.
    var manifest: SpeechModelManifest {
        let revision = "cdea3526163035c19915d4a10268992d018ebd46"
        let base = "https://huggingface.co/FluidInference/sensevoice-small-coreml/resolve/\(revision)/"
        let artifacts = [
            SpeechModelArtifact(
                id: "sensevoice-preprocessor-coremldata",
                relativePath: "SenseVoicePreprocessor.mlmodelc/coremldata.bin",
                remoteURL: URL(string: base + "SenseVoicePreprocessor.mlmodelc/coremldata.bin")!,
                sha256: "e64cc73b2a9b01bad799a23874bc20dba3cf3342c23e3f60012c3e884f682944",
                byteCount: 330
            ),
            SpeechModelArtifact(
                id: "sensevoice-preprocessor-model",
                relativePath: "SenseVoicePreprocessor.mlmodelc/model.mil",
                remoteURL: URL(string: base + "SenseVoicePreprocessor.mlmodelc/model.mil")!,
                sha256: "1b9b18be0a35b11165269b1ca071a30af736deb314d8bd82d9540c769137a70e",
                byteCount: 15_008
            ),
            SpeechModelArtifact(
                id: "sensevoice-preprocessor-weights",
                relativePath: "SenseVoicePreprocessor.mlmodelc/weights/weight.bin",
                remoteURL: URL(string: base + "SenseVoicePreprocessor.mlmodelc/weights/weight.bin")!,
                sha256: "69c630a115da5e4db36ec41662f0b776c0ef33ec6776d86f8cdaaba022518396",
                byteCount: 3_037_504
            ),
            SpeechModelArtifact(
                id: "sensevoice-int8-coremldata",
                relativePath: "SenseVoiceSmall_int8.mlmodelc/coremldata.bin",
                remoteURL: URL(string: base + "SenseVoiceSmall_int8.mlmodelc/coremldata.bin")!,
                sha256: "55ef1c194e641418817d7d07f6bfbd8032571e800b81264caba37eb63a95335b",
                byteCount: 436
            ),
            SpeechModelArtifact(
                id: "sensevoice-int8-model",
                relativePath: "SenseVoiceSmall_int8.mlmodelc/model.mil",
                remoteURL: URL(string: base + "SenseVoiceSmall_int8.mlmodelc/model.mil")!,
                sha256: "015fe7242a15eeb2fc0ca7f908ca3a09a5826b36e7d7f704803c8bbe60c1a148",
                byteCount: 1_134_696
            ),
            SpeechModelArtifact(
                id: "sensevoice-int8-weights",
                relativePath: "SenseVoiceSmall_int8.mlmodelc/weights/weight.bin",
                remoteURL: URL(string: base + "SenseVoiceSmall_int8.mlmodelc/weights/weight.bin")!,
                sha256: "dab122c65d5043cba5b47561d5c1d3a049dd123c662e802d9dbce8fdd0505a38",
                byteCount: 235_373_118
            ),
            SpeechModelArtifact(
                id: "sensevoice-vocabulary",
                relativePath: "vocab.json",
                remoteURL: URL(string: base + "vocab.json")!,
                sha256: "a2594fc1474e78973149cba8cd1f603ebed8c39c7decb470631f66e70ce58e97",
                byteCount: 352_064
            ),
        ]
        return SpeechModelManifest(
            id: "sensevoice-small-coreml-int8",
            version: revision,
            backend: "sensevoice-coreml",
            artifacts: artifacts
        )
    }

    var requiredRelativePaths: [String] {
        manifest.requiredRelativePaths
    }
}

struct SpeechSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var model: SpeechModelKind
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var soundEnabled: Bool
    var retentionDays: Int

    static let `default` = SpeechSettings(
        enabled: false,
        model: .senseVoice,
        hotkeyKeyCode: 15,
        hotkeyModifiers: 2048,
        soundEnabled: true,
        retentionDays: 30
    )
}

extension SpeechSettings {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case model
        case hotkeyKeyCode
        case hotkeyModifiers
        case soundEnabled
        case retentionDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        let storedModel = try container.decodeIfPresent(String.self, forKey: .model)
        model = SpeechModelKind(rawValue: storedModel ?? "") ?? .senseVoice
        hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? Self.default.hotkeyKeyCode
        hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? Self.default.hotkeyModifiers
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? Self.default.soundEnabled
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? Self.default.retentionDays
    }
}

struct SpeechHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let text: String
    let language: String?
    let createdAt: Date
    let duration: TimeInterval
    let audioFileName: String
}

enum SpeechRecognitionState: Equatable, Sendable {
    case idle
    case needsModel
    case requestingPermission
    case recording(TimeInterval)
    case transcribing
    case pasted
    case copied
    case cancelled
    case failed(String)

    var isActive: Bool {
        switch self {
        case .requestingPermission, .recording, .transcribing:
            return true
        default:
            return false
        }
    }
}
