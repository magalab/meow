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
