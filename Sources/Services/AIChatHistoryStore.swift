import Foundation

struct AIChatConversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [AIChatMessage]
    var createdAt: Date
    var updatedAt: Date
}

private struct AIChatConversationIndexEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
}

@MainActor
final class AIChatHistoryStore: ObservableObject {
    private enum Storage {
        static let legacyDefaultsKey = "meow.ai.chat-history"
        static let appSupportDirectoryName = "Meow"
        static let historyDirectoryName = "AIChats"
        static let conversationsDirectoryName = "conversations"
        static let indexFileName = "index.json"
        static let legacyFileName = "ai-chat-history.json"
    }

    private static let maxConversations = 50
    private static let maxMessagesPerConversation = 80
    private static let maxMessageLength = 100_000

    @Published private(set) var conversations: [AIChatConversation] = []
    @Published var selectedConversationID: UUID?

    private let fileManager = FileManager.default
    private var persistenceEnabled = true

    init() {
        load()
        selectedConversationID = conversations.first?.id
    }

    func selectedConversation() -> AIChatConversation? {
        guard let selectedConversationID else { return nil }
        return conversation(id: selectedConversationID)
    }

    func conversation(id: UUID) -> AIChatConversation? {
        conversations.first { $0.id == id }
    }

    func messages(for id: UUID?) -> [AIChatMessage] {
        guard let id else { return [] }
        return conversation(id: id)?.messages ?? []
    }

    @discardableResult
    func createConversation(select: Bool = true) -> UUID {
        let now = Date()
        let conversation = AIChatConversation(
            id: UUID(),
            title: "",
            messages: [],
            createdAt: now,
            updatedAt: now
        )
        conversations.insert(conversation, at: 0)
        if select {
            selectedConversationID = conversation.id
        }
        save()
        return conversation.id
    }

    @discardableResult
    func ensureSelectedConversation() -> UUID {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID })
        {
            return selectedConversationID
        }
        return createConversation()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        selectedConversationID = id
    }

    func append(_ message: AIChatMessage, to id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        var conversation = conversations[index]
        conversation.messages.append(trimmedMessage(message))
        if conversation.messages.count > Self.maxMessagesPerConversation {
            conversation.messages = Array(conversation.messages.suffix(Self.maxMessagesPerConversation))
        }
        if conversation.title.isEmpty,
           message.role == .user
        {
            conversation.title = title(from: message.content)
        }
        conversation.updatedAt = Date()

        conversations.remove(at: index)
        conversations.insert(conversation, at: 0)
        selectedConversationID = id
        prune()
        save()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationID == id {
            selectedConversationID = conversations.first?.id
        }
        save()
    }

    func clearAll() {
        conversations = []
        selectedConversationID = nil
        removePersistedHistory()
    }

    func setPersistenceEnabled(_ enabled: Bool) {
        guard persistenceEnabled != enabled else { return }
        persistenceEnabled = enabled
        if enabled {
            load()
            selectedConversationID = conversations.first?.id
        } else {
            clearAll()
        }
    }

    var storagePath: String {
        historyRootURL.path
    }

    var storageFolderURL: URL {
        historyRootURL
    }

    private func load() {
        guard persistenceEnabled else {
            conversations = []
            selectedConversationID = nil
            return
        }

        if let loaded = loadIndexedConversations() {
            conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
            prune()
            return
        }

        if let legacyFileConversations = loadLegacyFileConversations() {
            conversations = legacyFileConversations.sorted { $0.updatedAt > $1.updatedAt }
            prune()
            save()
            try? fileManager.removeItem(at: legacyHistoryFileURL)
            return
        }

        if let legacyData = UserDefaults.standard.data(forKey: Storage.legacyDefaultsKey),
           let decoded = try? JSONDecoder().decode([AIChatConversation].self, from: legacyData)
        {
            conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
            prune()
            save()
            UserDefaults.standard.removeObject(forKey: Storage.legacyDefaultsKey)
            return
        }

        conversations = []
    }

    private func save() {
        guard persistenceEnabled else { return }
        prune()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            try fileManager.createDirectory(at: conversationsDirectoryURL, withIntermediateDirectories: true)
            let index = conversations.map(indexEntry)
            let indexData = try encoder.encode(index)
            try indexData.write(to: indexFileURL, options: .atomic)

            let validFileNames = Set(conversations.map { conversationFileURL(for: $0.id).lastPathComponent })
            for conversation in conversations {
                let data = try encoder.encode(conversation)
                try data.write(to: conversationFileURL(for: conversation.id), options: .atomic)
            }
            removeOrphanConversationFiles(validFileNames: validFileNames)
            UserDefaults.standard.removeObject(forKey: Storage.legacyDefaultsKey)
            try? fileManager.removeItem(at: legacyHistoryFileURL)
        } catch {
            NSLog("[Meow AI] Failed to save chat history: \(error.localizedDescription)")
        }
    }

    private func removePersistedHistory() {
        try? fileManager.removeItem(at: historyRootURL)
        try? fileManager.removeItem(at: legacyHistoryFileURL)
        UserDefaults.standard.removeObject(forKey: Storage.legacyDefaultsKey)
    }

    private var appSupportMeowURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent(Storage.appSupportDirectoryName, isDirectory: true)
    }

    private var historyRootURL: URL {
        appSupportMeowURL.appendingPathComponent(Storage.historyDirectoryName, isDirectory: true)
    }

    private var conversationsDirectoryURL: URL {
        historyRootURL.appendingPathComponent(Storage.conversationsDirectoryName, isDirectory: true)
    }

    private var indexFileURL: URL {
        historyRootURL.appendingPathComponent(Storage.indexFileName)
    }

    private var legacyHistoryFileURL: URL {
        appSupportMeowURL.appendingPathComponent(Storage.legacyFileName)
    }

    private func conversationFileURL(for id: UUID) -> URL {
        conversationsDirectoryURL.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    private func loadIndexedConversations() -> [AIChatConversation]? {
        guard let indexData = try? Data(contentsOf: indexFileURL),
              let index = try? JSONDecoder().decode([AIChatConversationIndexEntry].self, from: indexData)
        else { return nil }

        let conversations = index.compactMap { entry -> AIChatConversation? in
            let fileURL = conversationFileURL(for: entry.id)
            guard let data = try? Data(contentsOf: fileURL),
                  let conversation = try? JSONDecoder().decode(AIChatConversation.self, from: data)
            else { return nil }
            return conversation
        }

        return conversations
    }

    private func loadLegacyFileConversations() -> [AIChatConversation]? {
        guard let data = try? Data(contentsOf: legacyHistoryFileURL),
              let decoded = try? JSONDecoder().decode([AIChatConversation].self, from: data)
        else { return nil }
        return decoded
    }

    private func indexEntry(from conversation: AIChatConversation) -> AIChatConversationIndexEntry {
        AIChatConversationIndexEntry(
            id: conversation.id,
            title: conversation.title,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messageCount: conversation.messages.count
        )
    }

    private func removeOrphanConversationFiles(validFileNames: Set<String>) {
        guard let files = try? fileManager.contentsOfDirectory(at: conversationsDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.pathExtension == "json" && !validFileNames.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func prune() {
        if conversations.count > Self.maxConversations {
            conversations = Array(conversations.prefix(Self.maxConversations))
        }
    }

    private func trimmedMessage(_ message: AIChatMessage) -> AIChatMessage {
        guard message.content.count > Self.maxMessageLength else { return message }
        return AIChatMessage(
            id: message.id,
            role: message.role,
            content: String(message.content.prefix(Self.maxMessageLength))
        )
    }

    private func title(from content: String) -> String {
        let singleLine = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !singleLine.isEmpty else { return "" }
        if singleLine.count <= 34 {
            return singleLine
        }
        return String(singleLine.prefix(34)) + "..."
    }
}
