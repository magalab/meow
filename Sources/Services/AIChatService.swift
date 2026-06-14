import AppKit
import Foundation

enum AIChatRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
}

struct AIChatMessage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let role: AIChatRole
    var content: String
    var imagePath: String?

    init(id: UUID = UUID(), role: AIChatRole, content: String, imagePath: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePath = imagePath
    }
}

struct AIChatInitialInput: Sendable {
    let text: String
    let imagePath: String?

    init(text: String, imagePath: String? = nil) {
        self.text = text
        self.imagePath = imagePath
    }
}

enum AIChatError: LocalizedError, Sendable {
    case notConfigured
    case invalidEndpoint
    case emptyResponse
    case imageUnavailable
    case visionUnsupported
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.aiErrorNotConfigured
        case .invalidEndpoint:
            return L10n.aiErrorInvalidEndpoint
        case .emptyResponse:
            return L10n.aiErrorEmptyResponse
        case .imageUnavailable:
            return L10n.aiErrorImageUnavailable
        case .visionUnsupported:
            return L10n.aiErrorVisionUnsupported
        case let .requestFailed(message):
            return message
        }
    }
}

struct AIChatService: Sendable {
    func fetchModels(settings: AISettings) async throws -> [String] {
        let endpoint = try modelsEndpoint(settings.endpoint)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            throw AIChatError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode)
        {
            throw AIChatError.requestFailed(errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data
            .map(\.id)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func send(messages: [AIChatMessage], settings: AISettings) async throws -> String {
        let endpoint = try normalizedEndpoint(settings.endpoint)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty, !model.isEmpty else {
            throw AIChatError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(messages: messages, settings: settings)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode)
        {
            throw AIChatError.requestFailed(errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIChatError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func requestBody(messages: [AIChatMessage], settings: AISettings) throws -> Data {
        try JSONEncoder().encode(
            ChatCompletionRequest(
                model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
                messages: try makePayloadMessages(
                    messages: messages,
                    settings: settings
                ),
                temperature: 0.7
            )
        )
    }

    private func normalizedEndpoint(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            throw AIChatError.invalidEndpoint
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "v1" {
            components.path = "/v1/chat/completions"
        } else if path.isEmpty {
            components.path = "/v1/chat/completions"
        }

        guard let url = components.url else {
            throw AIChatError.invalidEndpoint
        }
        return url
    }

    private func modelsEndpoint(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed) else {
            throw AIChatError.invalidEndpoint
        }

        let path = components.path
        if path.hasSuffix("/chat/completions") {
            components.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else if path.hasSuffix("/v1") {
            components.path = path + "/models"
        } else if path.isEmpty || path == "/" {
            components.path = "/v1/models"
        } else if !path.hasSuffix("/models") {
            components.path = path + "/models"
        }

        guard let url = components.url else {
            throw AIChatError.invalidEndpoint
        }
        return url
    }

    private func makePayloadMessages(
        messages: [AIChatMessage],
        settings: AISettings
    ) throws -> [ChatCompletionMessage] {
        var payload: [ChatCompletionMessage] = []
        let trimmedSystemPrompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystemPrompt.isEmpty {
            payload.append(ChatCompletionMessage(role: .system, content: .text(trimmedSystemPrompt)))
        }
        for message in messages {
            if message.role == .user, let imagePath = message.imagePath {
                guard settings.supportsVision else {
                    throw AIChatError.visionUnsupported
                }
                payload.append(
                    ChatCompletionMessage(
                        role: message.role,
                        content: .parts([
                            .text(message.content),
                            .imageURL(try dataURL(for: imagePath, settings: settings)),
                        ])
                    )
                )
            } else {
                payload.append(ChatCompletionMessage(role: message.role, content: .text(message.content)))
            }
        }
        return payload
    }

    private func dataURL(for path: String, settings: AISettings) throws -> String {
        guard let image = NSImage(contentsOfFile: path) else {
            throw AIChatError.imageUnavailable
        }

        let maxDimension = CGFloat(min(max(settings.imageMaxDimension, 512), 4_096))
        let sourceSize = image.size
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let prepared = scale < 1
            ? image.resized(
                to: NSSize(
                    width: max(1, sourceSize.width * scale),
                    height: max(1, sourceSize.height * scale)
                )
            )
            : image
        guard let cgImage = prepared.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AIChatError.imageUnavailable
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let quality = min(max(settings.imageJPEGQuality, 0.4), 1)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw AIChatError.imageUnavailable
        }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private func errorMessage(from data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(ChatCompletionErrorResponse.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return decoded.error.message
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatCompletionMessage]
    let temperature: Double
}

private struct ChatCompletionMessage: Encodable {
    let role: AIChatRole
    let content: ChatCompletionContent
}

private enum ChatCompletionContent: Encodable {
    case text(String)
    case parts([ChatCompletionContentPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .text(text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case let .parts(parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

private enum ChatCompletionContentPart: Encodable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private struct ImageURLPayload: Encodable {
        let url: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: url), forKey: .imageURL)
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct ChatCompletionErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}
