import Foundation

public enum AIChatError: Error, Equatable, Sendable {
    case notConfigured
    case invalidEndpoint
    case emptyResponse
    case imageUnavailable
    case visionUnsupported
    case requestFailed(statusCode: Int)
}

public struct AIChatClient: Sendable {
    public typealias ImageDataURLProvider = @Sendable (String, AISettings) throws -> String
    public typealias HTTPFailureLogger = @Sendable (_ operation: String, _ detail: String, _ statusCode: Int) -> Void

    private let imageDataURLProvider: ImageDataURLProvider
    private let httpFailureLogger: HTTPFailureLogger

    public init(
        imageDataURLProvider: @escaping ImageDataURLProvider,
        httpFailureLogger: @escaping HTTPFailureLogger
    ) {
        self.imageDataURLProvider = imageDataURLProvider
        self.httpFailureLogger = httpFailureLogger
    }

    public func fetchModels(settings: AISettings) async throws -> [String] {
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
            logHTTPFailure(operation: "Model fetch", data: data, statusCode: httpResponse.statusCode)
            throw AIChatError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data
            .map(\.id)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func send(messages: [AIChatMessage], settings: AISettings) async throws -> String {
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
            logHTTPFailure(operation: "Chat request", data: data, statusCode: httpResponse.statusCode)
            throw AIChatError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIChatError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func requestBody(messages: [AIChatMessage], settings: AISettings) throws -> Data {
        try JSONEncoder().encode(
            ChatCompletionRequest(
                model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
                messages: try makePayloadMessages(messages: messages, settings: settings),
                temperature: 0.7
            )
        )
    }

    public func normalizedEndpoint(_ rawValue: String) throws -> URL {
        var components = try validatedComponents(rawValue)

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "v1" || path.isEmpty {
            components.path = "/v1/chat/completions"
        }

        guard let url = components.url else {
            throw AIChatError.invalidEndpoint
        }
        return url
    }

    private func modelsEndpoint(_ rawValue: String) throws -> URL {
        var components = try validatedComponents(rawValue)

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

    private func validatedComponents(_ rawValue: String) throws -> URLComponents {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              scheme == "https" || (scheme == "http" && Self.isLoopback(host))
        else {
            throw AIChatError.invalidEndpoint
        }
        return components
    }

    private static func isLoopback(_ host: String) -> Bool {
        switch host.lowercased() {
        case "localhost", "127.0.0.1", "::1", "[::1]":
            true
        default:
            false
        }
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
                            .imageURL(try imageDataURLProvider(imagePath, settings)),
                        ])
                    )
                )
            } else {
                payload.append(ChatCompletionMessage(role: message.role, content: .text(message.content)))
            }
        }
        return payload
    }

    private func logHTTPFailure(operation: String, data: Data, statusCode: Int) {
        let detail = errorMessage(from: data) ?? "HTTP \(statusCode)"
        httpFailureLogger(operation, detail, statusCode)
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
