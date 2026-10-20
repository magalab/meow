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
