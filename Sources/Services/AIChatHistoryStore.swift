import Foundation

enum AIChatHistoryError: LocalizedError, Sendable {
    case attachmentStorageLimitExceeded

    var errorDescription: String? {
        L10n.aiErrorAttachmentStorageLimitExceeded
    }
}

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
        static let attachmentsDirectoryName = "attachments"
        static let indexFileName = "index.json"
        static let legacyFileName = "ai-chat-history.json"
    }

    private static let maxConversations = 50
    private static let maxMessagesPerConversation = 80
    private static let maxMessageLength = 100_000
    private static let maxAttachmentStorageBytes: Int64 = 256 * 1024 * 1024

    @Published private(set) var conversations: [AIChatConversation] = []
    @Published var selectedConversationID: UUID?

    private let fileManager = FileManager.default
    private let appSupportMeowURLOverride: URL?
    private var persistenceEnabled = true
    private var loadedConversationIDs = Set<UUID>()

    init(appSupportMeowURL: URL? = nil) {
        self.appSupportMeowURLOverride = appSupportMeowURL
        loadIndex()
        selectedConversationID = conversations.first?.id
    }

    func selectedConversation() -> AIChatConversation? {
        guard let selectedConversationID else { return nil }
        return conversation(id: selectedConversationID)
    }

    func conversation(id: UUID) -> AIChatConversation? {
        loadConversationBodyIfNeeded(id)
        return conversations.first { $0.id == id }
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
        loadedConversationIDs.insert(conversation.id)
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
        if !loadConversationBodyIfNeeded(id) {
            preserveUnreadableConversationFile(for: id)
            loadedConversationIDs.insert(id)
        }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }

        var conversation = conversations[index]
        conversation.messages.append(trimmedMessage(message))
        var shouldCleanupAttachments = false
        if conversation.messages.count > Self.maxMessagesPerConversation {
            conversation.messages = Array(conversation.messages.suffix(Self.maxMessagesPerConversation))
            shouldCleanupAttachments = true
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
        save(cleanupAttachments: shouldCleanupAttachments)
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        loadedConversationIDs.remove(id)
        if selectedConversationID == id {
            selectedConversationID = conversations.first?.id
        }
        save(cleanupAttachments: true)
    }

    func clearAll() {
        conversations = []
        loadedConversationIDs.removeAll()
        selectedConversationID = nil
        removePersistedHistory()
    }

    func setPersistenceEnabled(_ enabled: Bool) {
        guard persistenceEnabled != enabled else { return }
        persistenceEnabled = enabled
        if enabled {
            loadIndex()
            selectedConversationID = conversations.first?.id
        } else {
            clearAll()
        }
    }

    func storeAttachment(at sourceURL: URL) throws -> String {
        guard persistenceEnabled else {
            return sourceURL.path
        }
        let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = sourceValues.fileSize {
            let sourceBytes = Int64(fileSize)
            let storedBytes = try attachmentStorageBytes()
            guard sourceBytes <= Self.maxAttachmentStorageBytes,
                  storedBytes <= Self.maxAttachmentStorageBytes - sourceBytes
            else {
                throw AIChatHistoryError.attachmentStorageLimitExceeded
            }
        }
        try fileManager.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let destination = attachmentsDirectoryURL
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension(ext)
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination.path
    }

    var storagePath: String {
        historyRootURL.path
    }

    var storageFolderURL: URL {
        historyRootURL
    }

    private func loadIndex() {
        guard persistenceEnabled else {
            conversations = []
            selectedConversationID = nil
            return
        }
        loadedConversationIDs.removeAll()

        if let loaded = loadIndexedConversationsLightweight() {
            conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
            let didPrune = prune()
            if didPrune {
                save(cleanupAttachments: true)
            } else {
                removeOrphanAttachmentFiles()
            }
            return
        }

        if let loaded = loadLegacyFileConversations() {
            conversations = loaded.sorted { $0.updatedAt > $1.updatedAt }
            for conversation in conversations where !conversation.messages.isEmpty {
                loadedConversationIDs.insert(conversation.id)
            }
            prune()
            save(cleanupAttachments: true)
            try? fileManager.removeItem(at: legacyHistoryFileURL)
            return
        }

        if let legacyData = UserDefaults.standard.data(forKey: Storage.legacyDefaultsKey),
           let decoded = try? JSONDecoder().decode([AIChatConversation].self, from: legacyData)
        {
            conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
            for conversation in conversations where !conversation.messages.isEmpty {
                loadedConversationIDs.insert(conversation.id)
            }
            prune()
            save(cleanupAttachments: true)
            UserDefaults.standard.removeObject(forKey: Storage.legacyDefaultsKey)
            return
        }

        conversations = []
    }

    @discardableResult
    private func loadConversationBodyIfNeeded(_ id: UUID) -> Bool {
        guard !loadedConversationIDs.contains(id),
              let index = conversations.firstIndex(where: { $0.id == id })
        else { return true }

        let fileURL = conversationFileURL(for: id)
        do {
            let data = try Data(contentsOf: fileURL)
            let full = try JSONDecoder().decode(AIChatConversation.self, from: data)
            conversations[index] = full
            loadedConversationIDs.insert(id)
            return true
        } catch {
            MeowLog.ai.error(
                "Failed to load chat conversation \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            return false
        }
    }

    private func preserveUnreadableConversationFile(for id: UUID) {
        let fileURL = conversationFileURL(for: id)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        let preservedURL = fileURL.deletingPathExtension()
            .appendingPathExtension("invalid-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("json")
        do {
            try fileManager.moveItem(at: fileURL, to: preservedURL)
            MeowLog.ai.debug(
                "Preserved unreadable chat conversation at \(preservedURL.path, privacy: .private(mask: .hash))"
            )
        } catch {
            MeowLog.ai.error(
                "Failed to preserve unreadable chat conversation \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
        }
    }

    private func save(cleanupAttachments: Bool = false) {
        guard persistenceEnabled else { return }
        let didPrune = prune()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            try fileManager.createDirectory(at: conversationsDirectoryURL, withIntermediateDirectories: true)
            let index = conversations.map(indexEntry)
            let indexData = try encoder.encode(index)
            try indexData.write(to: indexFileURL, options: .atomic)

            let validFileNames = Set(conversations.map { conversationFileURL(for: $0.id).lastPathComponent })
            for conversation in conversations where loadedConversationIDs.contains(conversation.id) {
                let data = try encoder.encode(conversation)
                try data.write(to: conversationFileURL(for: conversation.id), options: .atomic)
            }
            removeOrphanConversationFiles(validFileNames: validFileNames)
            if cleanupAttachments || didPrune {
                removeOrphanAttachmentFiles()
            }
            UserDefaults.standard.removeObject(forKey: Storage.legacyDefaultsKey)
            try? fileManager.removeItem(at: legacyHistoryFileURL)
        } catch {
            MeowLog.ai.error(
                "Failed to save chat history: \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
        }
    }

    private func removePersistedHistory() {
        try? fileManager.removeItem(at: historyRootURL)
        try? fileManager.removeItem(at: legacyHistoryFileURL)
        UserDefaults.standard.removeObject(forKey: Storage.legacyDefaultsKey)
    }

    private var appSupportMeowURL: URL {
        if let appSupportMeowURLOverride {
            return appSupportMeowURLOverride
        }
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

    private var attachmentsDirectoryURL: URL {
        historyRootURL.appendingPathComponent(Storage.attachmentsDirectoryName, isDirectory: true)
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

    private func attachmentStorageBytes() throws -> Int64 {
        guard fileManager.fileExists(atPath: attachmentsDirectoryURL.path) else { return 0 }
        let files = try fileManager.contentsOfDirectory(
            at: attachmentsDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try files.reduce(Int64.zero) { total, file in
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values.fileSize ?? 0)
        }
    }

    private func loadIndexedConversationsLightweight() -> [AIChatConversation]? {
        guard let indexData = try? Data(contentsOf: indexFileURL),
              let index = try? JSONDecoder().decode([AIChatConversationIndexEntry].self, from: indexData)
        else { return nil }

        return index.map { entry in
            AIChatConversation(
                id: entry.id,
                title: entry.title,
                messages: [],
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )
        }
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
        for file in files
            where file.pathExtension == "json"
                && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil
                && !validFileNames.contains(file.lastPathComponent)
        {
            try? fileManager.removeItem(at: file)
        }
    }

    private func removeOrphanAttachmentFiles() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: attachmentsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        guard let referencedPaths = referencedAttachmentPaths() else {
            // Do not risk deleting an attachment when a retained conversation
            // cannot be decoded and its references are therefore unknown.
            return
        }

        let directoryPath = attachmentsDirectoryURL.standardizedFileURL.path
        let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        for file in files {
            guard file.standardizedFileURL.path.hasPrefix(directoryPrefix),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !referencedPaths.contains(file.standardizedFileURL.path)
            else {
                continue
            }
            do {
                try fileManager.removeItem(at: file)
            } catch {
                MeowLog.ai.debug(
                    "Unable to remove orphan chat attachment \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func referencedAttachmentPaths() -> Set<String>? {
        var paths = Set<String>()
        for conversation in conversations {
            let resolved: AIChatConversation?
            if loadedConversationIDs.contains(conversation.id) {
                resolved = conversation
            } else {
                let fileURL = conversationFileURL(for: conversation.id)
                guard let data = try? Data(contentsOf: fileURL),
                      let decoded = try? JSONDecoder().decode(AIChatConversation.self, from: data)
                else {
                    return nil
                }
                resolved = decoded
            }

            guard let resolved else { continue }
            for message in resolved.messages {
                guard let imagePath = message.imagePath else { continue }
                let fileURL = URL(fileURLWithPath: imagePath).standardizedFileURL
                let directoryPath = attachmentsDirectoryURL.standardizedFileURL.path
                let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
                if fileURL.path.hasPrefix(directoryPrefix) {
                    paths.insert(fileURL.path)
                }
            }
        }
        return paths
    }

    @discardableResult
    private func prune() -> Bool {
        guard conversations.count > Self.maxConversations else { return false }
        conversations = Array(conversations.prefix(Self.maxConversations))
        loadedConversationIDs.formIntersection(conversations.map(\.id))
        return true
    }

    private func trimmedMessage(_ message: AIChatMessage) -> AIChatMessage {
        guard message.content.count > Self.maxMessageLength else { return message }
        return AIChatMessage(
            id: message.id,
            role: message.role,
            content: String(message.content.prefix(Self.maxMessageLength)),
            imagePath: message.imagePath
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
