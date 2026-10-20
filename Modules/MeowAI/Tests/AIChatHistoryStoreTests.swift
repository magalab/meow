import Foundation
import MeowAI
import Testing

@Test("AI chat history uses the established index and conversation files")
@MainActor
func aiChatHistoryPersistsIndexAndConversation() throws {
    let root = aiChatHistoryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = AIChatHistoryStore(appSupportMeowURL: root)
    let conversationID = store.createConversation()
    store.append(AIChatMessage(role: .user, content: "Keep this history"), to: conversationID)

    let indexURL = root.appendingPathComponent("AIChats/index.json")
    let conversationURL = root
        .appendingPathComponent("AIChats/conversations", isDirectory: true)
        .appendingPathComponent("\(conversationID.uuidString.lowercased()).json")
    #expect(FileManager.default.fileExists(atPath: indexURL.path))

    let data = try Data(contentsOf: conversationURL)
    let decoded = try JSONDecoder().decode(AIChatConversation.self, from: data)
    #expect(decoded.id == conversationID)
    #expect(decoded.messages.map(\.content) == ["Keep this history"])

    let reloadedStore = AIChatHistoryStore(appSupportMeowURL: root)
    #expect(reloadedStore.conversations.map(\.id) == [conversationID])
    #expect(reloadedStore.messages(for: conversationID).map(\.content) == ["Keep this history"])
}

@Test("Deleting an AI conversation removes only its owned attachment")
@MainActor
func aiChatHistoryDeletesOwnedAttachment() throws {
    let root = aiChatHistoryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("source.png")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)

    let store = AIChatHistoryStore(appSupportMeowURL: root)
    let conversationID = store.createConversation()
    let attachmentPath = try store.storeAttachment(at: sourceURL)
    store.append(
        AIChatMessage(role: .user, content: "Image", imagePath: attachmentPath),
        to: conversationID
    )

    store.deleteConversation(conversationID)

    #expect(!FileManager.default.fileExists(atPath: attachmentPath))
    #expect(FileManager.default.fileExists(atPath: sourceURL.path))
}

@Test("AI chat history migrates the legacy JSON file in place")
@MainActor
func aiChatHistoryMigratesLegacyFile() throws {
    let root = aiChatHistoryTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let legacyURL = root.appendingPathComponent("ai-chat-history.json")
    let legacy = LegacyAIChatConversation(
        id: UUID(),
        title: "Legacy conversation",
        messages: [AIChatMessage(role: .user, content: "Keep me")],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    try JSONEncoder().encode([legacy]).write(to: legacyURL)

    let store = AIChatHistoryStore(appSupportMeowURL: root)

    #expect(store.conversations.map(\.title) == ["Legacy conversation"])
    #expect(store.messages(for: legacy.id).map(\.content) == ["Keep me"])
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("AIChats/index.json").path))
    #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
}

private func aiChatHistoryTestRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-AIHistory-Module-Test-\(UUID().uuidString)", isDirectory: true)
}

private struct LegacyAIChatConversation: Encodable {
    let id: UUID
    let title: String
    let messages: [AIChatMessage]
    let createdAt: Date
    let updatedAt: Date
}
