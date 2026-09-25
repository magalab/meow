import Foundation

enum TtsModelKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case system

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
        }
    }

    var description: String {
        switch self {
        case .system:
            return L10n.ttsModelSystemSubtitle
        }
    }

    var storageDirectoryName: String {
        switch self {
        case .system:
            return "system-voices"
        }
    }

    var requiredRelativePaths: [String] {
        []
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
        copy.model = .system
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
