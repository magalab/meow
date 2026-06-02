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

    init(id: UUID = UUID(), role: AIChatRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum AIChatError: LocalizedError, Sendable {
    case notConfigured
    case invalidEndpoint
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.aiErrorNotConfigured
        case .invalidEndpoint:
            return L10n.aiErrorInvalidEndpoint
        case .emptyResponse:
            return L10n.aiErrorEmptyResponse
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
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: makePayloadMessages(messages: messages, systemPrompt: settings.systemPrompt),
                temperature: 0.7
            )
        )

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

    private func makePayloadMessages(messages: [AIChatMessage], systemPrompt: String) -> [ChatCompletionMessage] {
        var payload: [ChatCompletionMessage] = []
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystemPrompt.isEmpty {
            payload.append(ChatCompletionMessage(role: .system, content: trimmedSystemPrompt))
        }
        payload += messages.map { ChatCompletionMessage(role: $0.role, content: $0.content) }
        return payload
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

private struct ChatCompletionMessage: Codable {
    let role: AIChatRole
    let content: String
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
