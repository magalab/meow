import Foundation

enum TtsModelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case matchaChineseEnglish
    case kokoroMultilingualInt8

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .matchaChineseEnglish:
            return L10n.ttsModelMatchaTitle
        case .kokoroMultilingualInt8:
            return L10n.ttsModelKokoroTitle
        }
    }

    var description: String {
        switch self {
        case .matchaChineseEnglish:
            return L10n.ttsModelMatchaSubtitle
        case .kokoroMultilingualInt8:
            return L10n.ttsModelKokoroSubtitle
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .matchaChineseEnglish:
            return "matcha-icefall-zh-en"
        case .kokoroMultilingualInt8:
            return "kokoro-int8-multi-lang-v1_1"
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
        case .kokoroMultilingualInt8:
            return TtsModelArchive(
                remoteURL: URL(
                    string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2"
                )!,
                fileName: "kokoro-int8-multi-lang-v1_1.tar.bz2",
                sha256: "a1e94694776049035c4f2c6529f003aaece993c76aae9a78995831c3c4dcafc6",
                approximateSizeMB: 140
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
        case .kokoroMultilingualInt8:
            return []
        }
    }

    var sourceURL: URL {
        switch self {
        case .matchaChineseEnglish:
            return URL(
                string: "https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/matcha-icefall-zh-en.html"
            )!
        case .kokoroMultilingualInt8:
            return URL(string: "https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html")!
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
        case .kokoroMultilingualInt8:
            return [
                "model.int8.onnx",
                "voices.bin",
                "tokens.txt",
                "espeak-ng-data",
                "lexicon-us-en.txt",
                "lexicon-zh.txt",
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

struct TtsVoice: Identifiable, Hashable, Sendable {
    let id: Int32
    let name: String
    let language: TtsVoiceLanguage

    var displayName: String {
        switch language {
        case .americanEnglish:
            return String(format: L10n.ttsVoiceAmericanEnglish, name)
        case .britishEnglish:
            return String(format: L10n.ttsVoiceBritishEnglish, name)
        case .chineseFemale:
            return String(format: L10n.ttsVoiceChineseFemale, name)
        case .chineseMale:
            return String(format: L10n.ttsVoiceChineseMale, name)
        }
    }

    private static let englishVoices: [TtsVoice] = [
        TtsVoice(id: 0, name: "Maple", language: .americanEnglish),
        TtsVoice(id: 1, name: "Sol", language: .americanEnglish),
        TtsVoice(id: 2, name: "Vale", language: .britishEnglish),
    ]

    private static let chineseFemaleNames = [
        "001", "002", "003", "004", "005", "006", "007", "008", "017", "018",
        "019", "021", "022", "023", "024", "026", "027", "028", "032", "036",
        "038", "039", "040", "042", "043", "044", "046", "047", "048", "049",
        "051", "059", "060", "067", "070", "071", "072", "073", "074", "075",
        "076", "077", "078", "079", "083", "084", "085", "086", "087", "088",
        "090", "092", "093", "094", "099",
    ]

    private static let chineseMaleNames = [
        "009", "010", "011", "012", "013", "014", "015", "016", "020", "025",
        "029", "030", "031", "033", "034", "035", "037", "041", "045", "050",
        "052", "053", "054", "055", "056", "057", "058", "061", "062", "063",
        "064", "065", "066", "068", "069", "080", "081", "082", "089", "091",
        "095", "096", "097", "098", "100",
    ]

    static let available: [TtsVoice] =
        englishVoices
        + chineseFemaleNames.enumerated().map { offset, name in
            TtsVoice(id: Int32(offset + 3), name: name, language: .chineseFemale)
        }
        + chineseMaleNames.enumerated().map { offset, name in
            TtsVoice(id: Int32(offset + 58), name: name, language: .chineseMale)
        }

    static func voice(for id: Int32) -> TtsVoice {
        available.first(where: { $0.id == id }) ?? available[3]
    }
}

enum TtsVoiceLanguage: Sendable {
    case americanEnglish
    case britishEnglish
    case chineseFemale
    case chineseMale
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
        if copy.model == .kokoroMultilingualInt8 {
            copy.model = .matchaChineseEnglish
        }
        copy.speed = 1
        copy.autoPlay = true
        if copy.model == .matchaChineseEnglish {
            copy.voiceID = 0
        } else if !TtsVoice.available.contains(where: { $0.id == voiceID }) {
            copy.voiceID = Self.default.voiceID
        }
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
