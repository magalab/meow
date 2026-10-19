import Foundation

public struct AISettings: Codable, Equatable, Sendable {
    public var endpoint: String
    public var apiKey: String
    public var model: String
    public var systemPrompt: String
    public var chatHistoryEnabled: Bool
    public var supportsVision: Bool
    public var imageMaxDimension: Int
    public var imageJPEGQuality: Double

    public var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static let `default` = AISettings(
        endpoint: "https://api.openai.com/v1/chat/completions",
        apiKey: "",
        model: "gpt-4o-mini",
        systemPrompt: "You are a concise, helpful assistant inside a lightweight macOS launcher.",
        chatHistoryEnabled: true,
        supportsVision: true,
        imageMaxDimension: 1600,
        imageJPEGQuality: 0.82
    )

    public init(
        endpoint: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        chatHistoryEnabled: Bool,
        supportsVision: Bool,
        imageMaxDimension: Int,
        imageJPEGQuality: Double
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.chatHistoryEnabled = chatHistoryEnabled
        self.supportsVision = supportsVision
        self.imageMaxDimension = imageMaxDimension
        self.imageJPEGQuality = imageJPEGQuality
    }
}

extension AISettings {
    // Decode the legacy apiKey field so SettingsStore can migrate existing users;
    // encoding intentionally omits it because the runtime value lives in Keychain.
    private enum CodingKeys: String, CodingKey {
        case endpoint
        case apiKey
        case model
        case systemPrompt
        case chatHistoryEnabled
        case supportsVision
        case imageMaxDimension
        case imageJPEGQuality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? Self.default.endpoint
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? Self.default.apiKey
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? Self.default.systemPrompt
        chatHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatHistoryEnabled) ?? Self.default.chatHistoryEnabled
        supportsVision = try container.decodeIfPresent(
            Bool.self,
            forKey: .supportsVision
        ) ?? Self.default.supportsVision
        imageMaxDimension = try container.decodeIfPresent(
            Int.self,
            forKey: .imageMaxDimension
        ) ?? Self.default.imageMaxDimension
        imageJPEGQuality = try container.decodeIfPresent(
            Double.self,
            forKey: .imageJPEGQuality
        ) ?? Self.default.imageJPEGQuality
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(model, forKey: .model)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(chatHistoryEnabled, forKey: .chatHistoryEnabled)
        try container.encode(supportsVision, forKey: .supportsVision)
        try container.encode(imageMaxDimension, forKey: .imageMaxDimension)
        try container.encode(imageJPEGQuality, forKey: .imageJPEGQuality)
    }
}
