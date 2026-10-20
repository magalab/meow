import Foundation
import MeowClipboard
import Testing

private func makeHistoryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MeowClipboardTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test("Clipboard history persists and deduplicates entries")
func clipboardHistoryPersistence() async throws {
    let directory = try makeHistoryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let firstEntry = ClipboardEntry(
        id: "first",
        content: .text("same clipboard text"),
        copiedAt: Date(timeIntervalSince1970: 100)
    )
    let inserted = try #require(
        await store.upsert(firstEntry, retention: .forever, imageStorageLimitMB: 128)
    )
    #expect(inserted.contains { $0.id == "first" })

    let duplicateEntry = ClipboardEntry(
        id: "second",
        content: .text("same clipboard text"),
        copiedAt: Date(timeIntervalSince1970: 200)
    )
    let deduplicated = try #require(
        await store.upsert(duplicateEntry, retention: .forever, imageStorageLimitMB: 128)
    )
    #expect(deduplicated.count == 1)
    #expect(deduplicated.first?.id == "second")
    #expect(deduplicated.first?.copiedAt == Date(timeIntervalSince1970: 200))
    await store.close()

    let reloadedStore = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let reloaded = try #require(
        await reloadedStore.load(retention: .forever, imageStorageLimitMB: 128)
    )
    #expect(reloaded == deduplicated)
    await reloadedStore.close()
}

@Test("Clipboard retention keeps pinned entries past the cutoff")
func clipboardHistoryRetentionPreservesPins() async throws {
    let directory = try makeHistoryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let oldDate = Date(timeIntervalSince1970: 1)
    let pinned = ClipboardEntry(
        id: "pinned",
        content: .text("keep"),
        copiedAt: oldDate,
        pinnedAt: oldDate
    )
    let recent = ClipboardEntry(
        id: "recent",
        content: .text("recent"),
        copiedAt: Date()
    )
    _ = try #require(await store.upsert(pinned, retention: .forever, imageStorageLimitMB: 128))
    _ = try #require(await store.upsert(recent, retention: .forever, imageStorageLimitMB: 128))

    let loaded = try #require(await store.load(retention: .day, imageStorageLimitMB: 128))
    #expect(Set(loaded.map(\.id)) == Set(["recent", "pinned"]))
    await store.close()
}
