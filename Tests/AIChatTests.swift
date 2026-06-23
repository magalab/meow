import AppKit
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@Test("Vision AI request includes an image data URL")
func visionAIRequestIncludesImageData() throws {
    let imageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: imageURL) }

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let red = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
    bitmap.setColor(red, atX: 0, y: 0)
    bitmap.setColor(red, atX: 1, y: 0)
    bitmap.setColor(red, atX: 0, y: 1)
    bitmap.setColor(red, atX: 1, y: 1)
    try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)

    let body = try AIChatService().requestBody(
        messages: [
            AIChatMessage(role: .user, content: "Analyze", imagePath: imageURL.path),
        ],
        settings: .default
    )
    let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(root["messages"] as? [[String: Any]])
    let userMessage = try #require(messages.last)
    let parts = try #require(userMessage["content"] as? [[String: Any]])
    let imagePart = try #require(parts.first { $0["type"] as? String == "image_url" })
    let imageURLPayload = try #require(imagePart["image_url"] as? [String: Any])
    let encodedURL = try #require(imageURLPayload["url"] as? String)
    #expect(encodedURL.hasPrefix("data:image/jpeg;base64,"))
}

@Test("Vision AI rejects image messages when capability is disabled")
func visionAIRejectsDisabledImageInput() throws {
    var settings = AISettings.default
    settings.supportsVision = false

    do {
        _ = try AIChatService().requestBody(
            messages: [
                AIChatMessage(role: .user, content: "Analyze", imagePath: "/tmp/image.png"),
            ],
            settings: settings
        )
        Issue.record("Expected image input to be rejected")
    } catch AIChatError.visionUnsupported {
        return
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("AI chat startup preserves attachments for indexed conversations")
@MainActor
func aiChatStartupPreservesIndexedAttachments() throws {
    let root = aiChatTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceImage = try makeAIChatTestImage()
    defer { try? FileManager.default.removeItem(at: sourceImage) }

    var store: AIChatHistoryStore? = AIChatHistoryStore(appSupportMeowURL: root)
    let conversationID = store!.createConversation()
    let attachmentPath = try store!.storeAttachment(at: sourceImage)
    store!.append(
        AIChatMessage(role: .user, content: "Analyze this image", imagePath: attachmentPath),
        to: conversationID
    )
    #expect(FileManager.default.fileExists(atPath: attachmentPath))

    store = AIChatHistoryStore(appSupportMeowURL: root)
    #expect(store!.conversations.map(\.id).contains(conversationID))
    #expect(FileManager.default.fileExists(atPath: attachmentPath))
}

@Test("AI chat append preserves attachments from unloaded conversations")
@MainActor
func aiChatAppendPreservesUnloadedConversationAttachments() throws {
    let root = aiChatTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceImage = try makeAIChatTestImage()
    defer { try? FileManager.default.removeItem(at: sourceImage) }

    var store: AIChatHistoryStore? = AIChatHistoryStore(appSupportMeowURL: root)
    let imageConversationID = store!.createConversation()
    let attachmentPath = try store!.storeAttachment(at: sourceImage)
    store!.append(
        AIChatMessage(role: .user, content: "Analyze this image", imagePath: attachmentPath),
        to: imageConversationID
    )
    let textConversationID = store!.createConversation()
    store!.append(AIChatMessage(role: .user, content: "Hello"), to: textConversationID)

    store = AIChatHistoryStore(appSupportMeowURL: root)
    store!.append(AIChatMessage(role: .assistant, content: "Hi"), to: textConversationID)

    #expect(FileManager.default.fileExists(atPath: attachmentPath))
    #expect(store!.messages(for: imageConversationID).first?.imagePath == attachmentPath)
}

@Test("AI chat append preserves unreadable body and saves the new message")
@MainActor
func aiChatAppendAfterUnreadableBodyPersistsNewMessage() throws {
    let root = aiChatTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    var store: AIChatHistoryStore? = AIChatHistoryStore(appSupportMeowURL: root)
    let conversationID = store!.createConversation()
    store!.append(AIChatMessage(role: .user, content: "Old message"), to: conversationID)
    try Data("not json".utf8).write(to: aiChatConversationFileURL(root: root, id: conversationID))

    store = AIChatHistoryStore(appSupportMeowURL: root)
    store!.append(AIChatMessage(role: .user, content: "New message"), to: conversationID)

    let savedData = try Data(contentsOf: aiChatConversationFileURL(root: root, id: conversationID))
    let savedConversation = try JSONDecoder().decode(AIChatConversation.self, from: savedData)
    #expect(savedConversation.messages.map(\.content) == ["New message"])

    let conversationFiles = try FileManager.default.contentsOfDirectory(
        at: aiChatConversationsDirectoryURL(root: root),
        includingPropertiesForKeys: nil
    )
    #expect(conversationFiles.contains { file in
        file.lastPathComponent.hasPrefix("\(conversationID.uuidString.lowercased()).invalid-")
            && file.lastPathComponent.hasSuffix(".json")
    })
}

private func aiChatTestRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-AIHistory-Test-\(UUID().uuidString)", isDirectory: true)
}

private func makeAIChatTestImage() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-AIHistory-Image-\(UUID().uuidString)")
        .appendingPathExtension("png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
    return url
}

private func aiChatConversationFileURL(root: URL, id: UUID) -> URL {
    aiChatConversationsDirectoryURL(root: root)
        .appendingPathComponent("\(id.uuidString.lowercased()).json")
}

private func aiChatConversationsDirectoryURL(root: URL) -> URL {
    root.appendingPathComponent("AIChats", isDirectory: true)
        .appendingPathComponent("conversations", isDirectory: true)
}
