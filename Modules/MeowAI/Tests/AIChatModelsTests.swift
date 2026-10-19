import Foundation
import MeowAI
import Testing

@Test("AI settings decode legacy API keys and encode without them")
func aiSettingsPreserveLegacyKeyMigrationCompatibility() throws {
    let legacy = Data(#"{"endpoint":"https://example.com/v1","apiKey":"legacy-key"}"#.utf8)
    let decoded = try JSONDecoder().decode(AISettings.self, from: legacy)

    #expect(decoded.apiKey == "legacy-key")
    #expect(decoded.model == AISettings.default.model)

    let encoded = try JSONEncoder().encode(decoded)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["apiKey"] == nil)
}

@Test("AI chat messages retain their persisted JSON shape")
func aiChatMessageCodableShapeRemainsCompatible() throws {
    let id = try #require(UUID(uuidString: "2D7BB018-9825-4E93-92E1-5DCBA8CEBDEB"))
    let message = AIChatMessage(id: id, role: .user, content: "Hello", imagePath: "/tmp/image.png")
    let encoded = try JSONEncoder().encode(message)
    let decoded = try JSONDecoder().decode(AIChatMessage.self, from: encoded)

    #expect(decoded == message)
    #expect(decoded.id == id)
}

@Test("AI client normalizes service endpoints and rejects insecure hosts")
func aiClientEndpointValidation() throws {
    let client = AIChatClient(
        imageDataURLProvider: { _, _ in throw AIChatError.imageUnavailable },
        httpFailureLogger: { _, _, _ in }
    )

    #expect(try client.normalizedEndpoint("https://api.example.com/v1").absoluteString == "https://api.example.com/v1/chat/completions")
    #expect(throws: AIChatError.invalidEndpoint) {
        try client.normalizedEndpoint("http://api.example.com/v1")
    }
}

@Test("AI client builds the configured system prompt and chat turns")
func aiClientBuildsChatRequestBody() throws {
    let client = AIChatClient(
        imageDataURLProvider: { _, _ in "data:image/jpeg;base64,AA==" },
        httpFailureLogger: { _, _, _ in }
    )
    var settings = AISettings.default
    settings.model = "  test-model  "
    settings.systemPrompt = "  Be concise.  "

    let body = try client.requestBody(
        messages: [AIChatMessage(role: .user, content: "Hello")],
        settings: settings
    )
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])

    #expect(object["model"] as? String == "test-model")
    #expect(messages.map { $0["role"] as? String } == ["system", "user"])
    #expect(messages.first?["content"] as? String == "Be concise.")
    #expect(messages.last?["content"] as? String == "Hello")
}

@Test("AI client fetches and sorts model names through its HTTP loader")
func aiClientFetchesModels() async throws {
    let endpoint = try #require(URL(string: "https://api.example.com/v1/models"))
    let response = try #require(HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil))
    let body = Data(#"{"data":[{"id":"z-model"},{"id":"a-model"},{"id":"  "}]}"#.utf8)
    let client = AIChatClient(
        imageDataURLProvider: { _, _ in "" },
        httpFailureLogger: { _, _, _ in },
        httpDataLoader: { request in
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            return (body, response)
        }
    )
    var settings = AISettings.default
    settings.apiKey = "test-key"

    #expect(try await client.fetchModels(settings: settings) == ["a-model", "z-model"])
}

@Test("AI client parses a chat completion and rejects HTTP errors")
func aiClientSendsAndParsesChatCompletion() async throws {
    let endpoint = try #require(URL(string: "https://api.example.com/v1/chat/completions"))
    let successResponse = try #require(HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil))
    let completionBody = Data(#"{"choices":[{"message":{"content":"  answer  "}}]}"#.utf8)
    let client = AIChatClient(
        imageDataURLProvider: { _, _ in "" },
        httpFailureLogger: { _, _, _ in },
        httpDataLoader: { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            return (completionBody, successResponse)
        }
    )
    var settings = AISettings.default
    settings.apiKey = "test-key"

    #expect(try await client.send(messages: [], settings: settings) == "answer")

    let errorResponse = try #require(HTTPURLResponse(url: endpoint, statusCode: 401, httpVersion: nil, headerFields: nil))
    let errorBody = Data(#"{"error":{"message":"unauthorized"}}"#.utf8)
    let failingClient = AIChatClient(
        imageDataURLProvider: { _, _ in "" },
        httpFailureLogger: { _, _, _ in },
        httpDataLoader: { _ in (errorBody, errorResponse) }
    )
    do {
        _ = try await failingClient.send(messages: [], settings: settings)
        Issue.record("Expected an HTTP status error")
    } catch let error as AIChatError {
        #expect(error == .requestFailed(statusCode: 401))
    }
}
