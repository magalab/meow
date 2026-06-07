import Foundation

enum SpeechModelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case senseVoice = "senseVoice"
    case parakeetEnglish = "parakeetEnglish"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .senseVoice:
            return L10n.speechModelSenseVoiceTitle
        case .parakeetEnglish:
            return L10n.speechModelParakeetTitle
        }
    }

    var description: String {
        switch self {
        case .senseVoice:
            return L10n.speechModelSenseVoiceSubtitle
        case .parakeetEnglish:
            return L10n.speechModelParakeetSubtitle
        }
    }

    var downloadConfirmTitle: String {
        switch self {
        case .senseVoice:
            return L10n.speechModelSenseVoiceDownloadConfirmTitle
        case .parakeetEnglish:
            return L10n.speechModelParakeetDownloadConfirmTitle
        }
    }

    var downloadConfirmMessage: String {
        switch self {
        case .senseVoice:
            return L10n.speechModelSenseVoiceDownloadConfirmMessage
        case .parakeetEnglish:
            return L10n.speechModelParakeetDownloadConfirmMessage
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .senseVoice:
            return "sense-voice-2024-07-17"
        case .parakeetEnglish:
            return "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8"
        }
    }

    var modelFileName: String {
        "model.int8.onnx"
    }

    var tokensFileName: String {
        "tokens.txt"
    }

    var downloadSource: SpeechModelDownloadSource {
        switch self {
        case .senseVoice:
            return .files(
                [
                    SpeechModelDownloadFile(
                        remoteURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx")!,
                        localFileName: "model.int8.onnx",
                        sha256: "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
                    ),
                    SpeechModelDownloadFile(
                        remoteURL: URL(string: "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt")!,
                        localFileName: "tokens.txt",
                        sha256: "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"
                    ),
                ]
            )
        case .parakeetEnglish:
            return .archive(
                SpeechModelArchiveDownload(
                    remoteURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2")!,
                    localFileName: "sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2",
                    sha256: "17f945007b52ccd8b7200ffc7c5652e9e8e961dfdf479cefcabd06cf5703630b"
                )
            )
        }
    }

    var recognitionFlavor: SpeechRecognitionFlavor {
        switch self {
        case .senseVoice:
            return .senseVoice
        case .parakeetEnglish:
            return .nemoCtc
        }
    }
}

enum SpeechRecognitionFlavor: Sendable {
    case senseVoice
    case nemoCtc
}

enum SpeechModelDownloadSource: Sendable {
    case files([SpeechModelDownloadFile])
    case archive(SpeechModelArchiveDownload)
}

struct SpeechModelDownloadFile: Sendable {
    let remoteURL: URL
    let localFileName: String
    let sha256: String
}

struct SpeechModelArchiveDownload: Sendable {
    let remoteURL: URL
    let localFileName: String
    let sha256: String
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
        model = try container.decodeIfPresent(SpeechModelKind.self, forKey: .model) ?? Self.default.model
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
