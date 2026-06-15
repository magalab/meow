import Foundation

enum TtsModelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case matchaChineseEnglish

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = TtsModelKind(rawValue: rawValue) ?? .matchaChineseEnglish
    }

    var displayName: String {
        switch self {
        case .matchaChineseEnglish:
            return L10n.ttsModelMatchaTitle
        }
    }

    var description: String {
        switch self {
        case .matchaChineseEnglish:
            return L10n.ttsModelMatchaSubtitle
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .matchaChineseEnglish:
            return "matcha-icefall-zh-en"
        }
    }

    var archive: TtsModelArchive {
        switch self {
        case .matchaChineseEnglish:
            return TtsModelArchive(
                remoteURL: URL(
                    string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/matcha-icefall-zh-en.tar.bz2"
                )!,
                fileName: "matcha-icefall-zh-en.tar.bz2",
                sha256: nil,
                approximateSizeMB: 90
            )
        }
    }

    var additionalFiles: [TtsModelFile] {
        switch self {
        case .matchaChineseEnglish:
            return [
                TtsModelFile(
                    remoteURL: URL(
                        string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos-16khz-univ.onnx"
                    )!,
                    relativePath: "vocos-16khz-univ.onnx",
                    sha256: nil,
                    approximateSizeMB: 51
                ),
            ]
        }
    }

    var sourceURL: URL {
        switch self {
        case .matchaChineseEnglish:
            return URL(
                string: "https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/matcha-icefall-zh-en.html"
            )!
        }
    }

    var downloadSizeMB: Int {
        archive.approximateSizeMB + additionalFiles.reduce(0) { $0 + $1.approximateSizeMB }
    }

    var requiredRelativePaths: [String] {
        switch self {
        case .matchaChineseEnglish:
            return [
                "model-steps-3.onnx",
                "vocos-16khz-univ.onnx",
                "tokens.txt",
                "espeak-ng-data",
                "lexicon.txt",
                "date-zh.fst",
                "phone-zh.fst",
                "number-zh.fst",
            ]
        }
    }
}

struct TtsModelArchive: Sendable {
    let remoteURL: URL
    let fileName: String
    let sha256: String?
    let approximateSizeMB: Int
}

struct TtsModelFile: Sendable {
    let remoteURL: URL
    let relativePath: String
    let sha256: String?
    let approximateSizeMB: Int
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
        model: .matchaChineseEnglish,
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
        copy.model = .matchaChineseEnglish
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
