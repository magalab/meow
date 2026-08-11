import AppKit
import Foundation
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

private func makeClipboardTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Meow-ClipboardHistory-Test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func textEntry(
    _ text: String,
    copiedAt: Date = Date(),
    pinnedAt: Date? = nil
) -> ClipboardEntry {
    ClipboardEntry(
        id: UUID().uuidString,
        content: .text(text),
        copiedAt: copiedAt,
        sourceBundleID: "com.example.source",
        pinnedAt: pinnedAt
    )
}

@Test("Clipboard history persists, deduplicates, and reloads")
func clipboardHistoryPersistenceAndDeduplication() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let first = textEntry("persistent clipboard value", copiedAt: Date(timeIntervalSince1970: 10))
    let replacement = textEntry("persistent clipboard value", copiedAt: Date(timeIntervalSince1970: 20))
    _ = await store.upsert(first, retention: .forever, imageStorageLimitMB: 16)
    let snapshot = try #require(
        await store.upsert(replacement, retention: .forever, imageStorageLimitMB: 16)
    )
    #expect(snapshot.count == 1)
    #expect(snapshot.first?.id == replacement.id)
    #expect(snapshot.first?.copiedAt == replacement.copiedAt)
    await store.close()

    let reloaded = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let restored = try #require(await reloaded.load(retention: .forever, imageStorageLimitMB: 16))
    #expect(restored.count == 1)
    #expect(restored.first?.content == .text("persistent clipboard value"))
    await reloaded.close()
}

@Test("Deduplicating a pinned entry preserves its identity and pin state")
func clipboardPinnedDeduplication() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let pinnedAt = Date(timeIntervalSince1970: 10)
    let pinned = textEntry(
        "persistent pinned value",
        copiedAt: Date(timeIntervalSince1970: 20),
        pinnedAt: pinnedAt
    )
    let duplicate = textEntry(
        "persistent pinned value",
        copiedAt: Date(timeIntervalSince1970: 30)
    )

    _ = await store.upsert(pinned, retention: .forever, imageStorageLimitMB: 16)
    let snapshot = try #require(
        await store.upsert(duplicate, retention: .forever, imageStorageLimitMB: 16)
    )
    let restored = try #require(snapshot.first)

    #expect(snapshot.count == 1)
    #expect(restored.id == pinned.id)
    #expect(restored.pinnedAt == pinnedAt)
    #expect(restored.copiedAt == duplicate.copiedAt)
    await store.close()
}

@Test("Clipboard retention prunes old unpinned entries but preserves pins")
func clipboardRetentionPreservesPins() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let oldDate = Date().addingTimeInterval(-10 * 86_400)
    let oldRegular = textEntry("old regular", copiedAt: oldDate)
    let oldPinned = textEntry("old pinned", copiedAt: oldDate, pinnedAt: oldDate)
    let recent = textEntry("recent")

    _ = await store.upsert(oldRegular, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.upsert(oldPinned, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.upsert(recent, retention: .forever, imageStorageLimitMB: 16)
    let pruned = try #require(await store.enforce(retention: .day, imageStorageLimitMB: 16))

    #expect(!pruned.contains { $0.id == oldRegular.id })
    #expect(pruned.contains { $0.id == oldPinned.id && $0.isPinned })
    #expect(pruned.contains { $0.id == recent.id })
    await store.close()
}

@Test("Forever retention keeps old clipboard entries")
func clipboardForeverRetention() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let old = textEntry("keep forever", copiedAt: Date(timeIntervalSince1970: 1))

    _ = await store.upsert(old, retention: .forever, imageStorageLimitMB: 16)
    let entries = try #require(await store.enforce(retention: .forever, imageStorageLimitMB: 16))
    #expect(entries.contains { $0.id == old.id })
    await store.close()
}

@Test("Full-text search reaches entries outside the in-memory window")
func clipboardSearchBeyondMemoryWindow() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)

    for index in 0 ..< 120 {
        let text = index == 0 ? "archived-nebula-value" : "recent item \(index)"
        let entry = textEntry(text, copiedAt: Date(timeIntervalSince1970: TimeInterval(index + 1)))
        _ = await store.upsert(entry, retention: .forever, imageStorageLimitMB: 16)
    }

    let window = try #require(await store.load(retention: .forever, imageStorageLimitMB: 16))
    #expect(window.count == 100)
    #expect(!window.contains { $0.content == .text("archived-nebula-value") })

    let search = try #require(await store.search("nebula", limit: 200))
    #expect(search.contains { $0.content == .text("archived-nebula-value") })
    await store.close()
}

@MainActor
@Test("Database-only search results can be pinned")
func clipboardPinBeyondMemoryWindow() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let historyStore = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    var archivedEntry: ClipboardEntry?
    for index in 0 ..< 120 {
        let entry = textEntry(
            index == 0 ? "off-window-pin-target" : "recent pin item \(index)",
            copiedAt: Date(timeIntervalSince1970: TimeInterval(index + 1))
        )
        if index == 0 { archivedEntry = entry }
        _ = await historyStore.upsert(entry, retention: .forever, imageStorageLimitMB: 16)
    }
    await historyStore.close()

    let store = ClipboardStore(historyDirectory: directory, memoryWindow: 100)
    store.configure(
        retention: .forever,
        imageStorageLimitMB: 512,
        disabledAppBundleIDs: []
    )
    store.startMonitoring {}
    await store.waitForPendingPersistence()
    let archived = try #require(archivedEntry)
    #expect(!store.getEntries().contains { $0.id == archived.id })

    let result = try #require(await store.search("off-window-pin-target").first)
    store.togglePinned(result)
    #expect(store.getEntries().contains { $0.id == archived.id && $0.isPinned })
    await store.waitForPendingPersistence()
    let persisted = try #require(await store.search("off-window-pin-target").first)
    #expect(persisted.isPinned)
    store.stopMonitoring()
}

@Test("Short search restores URL and file clipboard entries")
func clipboardShortSearchAndKinds() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let url = try #require(URL(string: "https://example.com/xy-reference"))
    let fileURL = directory.appendingPathComponent("xy-notes.md")
    let urlEntry = ClipboardEntry(
        id: UUID().uuidString,
        content: .url(url),
        copiedAt: Date(timeIntervalSince1970: 1)
    )
    let fileEntry = ClipboardEntry(
        id: UUID().uuidString,
        content: .file(FileClipboardContent(url: fileURL, name: fileURL.lastPathComponent)),
        copiedAt: Date(timeIntervalSince1970: 2)
    )

    _ = await store.upsert(urlEntry, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.upsert(fileEntry, retention: .forever, imageStorageLimitMB: 16)
    let results = try #require(await store.search("xy", limit: 200))
    #expect(results.contains { $0.content == urlEntry.content })
    #expect(results.contains { $0.content == fileEntry.content })
    await store.close()

    let reloaded = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let restored = try #require(await reloaded.load(retention: .forever, imageStorageLimitMB: 16))
    #expect(restored.contains { $0.content == urlEntry.content })
    #expect(restored.contains { $0.content == fileEntry.content })
    await reloaded.close()
}

@Test("Short search treats SQL wildcard characters literally")
func clipboardShortSearchEscapesWildcards() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let percent = textEntry("100% complete")
    let underscore = textEntry("under_score")
    let backslash = textEntry(#"folder\name"#)
    let ordinary = textEntry("ordinary value")

    for entry in [percent, underscore, backslash, ordinary] {
        _ = await store.upsert(entry, retention: .forever, imageStorageLimitMB: 16)
    }

    let percentResults = try #require(await store.search("%", limit: 200))
    #expect(percentResults.map(\.id) == [percent.id])
    let underscoreResults = try #require(await store.search("_", limit: 200))
    #expect(underscoreResults.map(\.id) == [underscore.id])
    let backslashResults = try #require(await store.search(#"\"#, limit: 200))
    #expect(backslashResults.map(\.id) == [backslash.id])
    await store.close()
}

@Test("Pin state persists and unpinning moves an entry to recent history")
func clipboardPinPersistence() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let entry = textEntry("pin me", copiedAt: Date(timeIntervalSince1970: 1))
    _ = await store.upsert(entry, retention: .forever, imageStorageLimitMB: 16)

    let pinned = try #require(await store.setPinned(id: entry.id, pinned: true))
    #expect(pinned.first(where: { $0.id == entry.id })?.isPinned == true)
    let unpinned = try #require(await store.setPinned(id: entry.id, pinned: false))
    let updated = try #require(unpinned.first(where: { $0.id == entry.id }))
    #expect(!updated.isPinned)
    #expect(updated.copiedAt > entry.copiedAt)
    await store.close()
}

@Test("Deleting image history removes owned files and leaves external files")
func clipboardOwnedImageCleanup() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let images = directory.appendingPathComponent("images", isDirectory: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let ownedThumbnail = images.appendingPathComponent("owned-thumb.png")
    let ownedOriginal = images.appendingPathComponent("owned.png")
    let external = directory.deletingLastPathComponent().appendingPathComponent("external-\(UUID()).png")
    try Data([1, 2, 3]).write(to: ownedThumbnail)
    try Data([4, 5, 6]).write(to: ownedOriginal)
    try Data([7, 8, 9]).write(to: external)
    defer { try? FileManager.default.removeItem(at: external) }

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let owned = ClipboardEntry(
        id: UUID().uuidString,
        content: .image(
            ImageClipboardContent(
                thumbnailPath: ownedThumbnail.path,
                originalPath: ownedOriginal.path,
                sourceName: "owned.png",
                width: 10,
                height: 10,
                ownsCachedFiles: true,
                contentHash: ClipboardContent.sha256(Data("owned".utf8))
            )
        ),
        copiedAt: Date()
    )
    let externalEntry = ClipboardEntry(
        id: UUID().uuidString,
        content: .image(
            ImageClipboardContent(
                thumbnailPath: external.path,
                originalPath: external.path,
                sourceName: "external.png",
                width: 10,
                height: 10,
                ownsCachedFiles: false,
                contentHash: ClipboardContent.sha256(Data("external".utf8))
            )
        ),
        copiedAt: Date()
    )

    _ = await store.upsert(owned, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.upsert(externalEntry, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.remove(id: owned.id)
    _ = await store.remove(id: externalEntry.id)

    #expect(!FileManager.default.fileExists(atPath: ownedThumbnail.path))
    #expect(!FileManager.default.fileExists(atPath: ownedOriginal.path))
    #expect(FileManager.default.fileExists(atPath: external.path))
    await store.close()
}

@Test("Pending images survive orphan scans and are materialized during upsert")
func clipboardPendingImageMaterialization() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let pending = directory.appendingPathComponent("pending-images", isDirectory: true)
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    let thumbnail = pending.appendingPathComponent("pending-thumb.png")
    let original = pending.appendingPathComponent("pending.png")
    try Data([1, 2, 3]).write(to: thumbnail)
    try Data([4, 5, 6]).write(to: original)
    let entry = ClipboardEntry(
        id: UUID().uuidString,
        content: .image(
            ImageClipboardContent(
                thumbnailPath: thumbnail.path,
                originalPath: original.path,
                sourceName: "pending.png",
                width: 10,
                height: 10,
                ownsCachedFiles: true,
                contentHash: ClipboardContent.sha256(Data("pending".utf8))
            )
        ),
        copiedAt: Date()
    )
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)

    _ = await store.load(retention: .forever, imageStorageLimitMB: 16)
    #expect(FileManager.default.fileExists(atPath: thumbnail.path))
    #expect(FileManager.default.fileExists(atPath: original.path))

    let snapshot = try #require(
        await store.upsert(entry, retention: .forever, imageStorageLimitMB: 16)
    )
    let stored = try #require(snapshot.first(where: { $0.id == entry.id }))
    guard case let .image(image) = stored.content else {
        Issue.record("Expected an image entry")
        return
    }
    #expect(image.thumbnailPath.hasPrefix(directory.appendingPathComponent("images").path))
    #expect(FileManager.default.fileExists(atPath: image.thumbnailPath))
    #expect(image.originalPath.map(FileManager.default.fileExists(atPath:)) == true)
    #expect(!FileManager.default.fileExists(atPath: thumbnail.path))
    #expect(!FileManager.default.fileExists(atPath: original.path))
    await store.close()
}

@Test("Owned audio cache files are deleted and external audio files are preserved")
func clipboardAudioCleanup() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let ownedURL = directory.deletingLastPathComponent()
        .appendingPathComponent("owned-audio-\(UUID()).m4a")
    let externalURL = directory.deletingLastPathComponent()
        .appendingPathComponent("external-audio-\(UUID()).m4a")
    try Data([1, 2, 3]).write(to: ownedURL)
    try Data([4, 5, 6]).write(to: externalURL)
    defer {
        try? FileManager.default.removeItem(at: ownedURL)
        try? FileManager.default.removeItem(at: externalURL)
    }
    let owned = ClipboardEntry(
        id: UUID().uuidString,
        content: .audio(
            AudioClipboardContent(
                cachePath: ownedURL.path,
                name: ownedURL.lastPathComponent,
                duration: 1,
                ownsCachedFile: true
            )
        ),
        copiedAt: Date()
    )
    let external = ClipboardEntry(
        id: UUID().uuidString,
        content: .audio(
            AudioClipboardContent(
                cachePath: externalURL.path,
                name: externalURL.lastPathComponent,
                duration: 1,
                ownsCachedFile: false
            )
        ),
        copiedAt: Date()
    )
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    _ = await store.upsert(owned, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.upsert(external, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.remove(id: owned.id)
    _ = await store.remove(id: external.id)
    #expect(!FileManager.default.fileExists(atPath: ownedURL.path))
    #expect(FileManager.default.fileExists(atPath: externalURL.path))
    await store.close()
}

@Test("Loading removes orphan images and clearing removes all owned history")
func clipboardOrphanCleanupAndClearAll() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let images = directory.appendingPathComponent("images", isDirectory: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let referenced = images.appendingPathComponent("referenced.png")
    let orphan = images.appendingPathComponent("orphan.png")
    try Data([1, 2, 3]).write(to: referenced)
    try Data([4, 5, 6]).write(to: orphan)
    let imageEntry = ClipboardEntry(
        id: UUID().uuidString,
        content: .image(
            ImageClipboardContent(
                thumbnailPath: referenced.path,
                originalPath: nil,
                sourceName: referenced.lastPathComponent,
                width: 10,
                height: 10,
                ownsCachedFiles: true,
                contentHash: ClipboardContent.sha256(Data("referenced".utf8))
            )
        ),
        copiedAt: Date()
    )
    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    _ = await store.upsert(imageEntry, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.load(retention: .forever, imageStorageLimitMB: 16)
    #expect(FileManager.default.fileExists(atPath: referenced.path))
    #expect(!FileManager.default.fileExists(atPath: orphan.path))

    let cleared = try #require(await store.clearAll())
    #expect(cleared.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: referenced.path))
    let reloaded = try #require(await store.load(retention: .forever, imageStorageLimitMB: 16))
    #expect(reloaded.isEmpty)
    await store.close()
}

@Test("Image storage limit removes the oldest unpinned image")
func clipboardImageStorageLimit() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let images = directory.appendingPathComponent("images", isDirectory: true)
    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
    let firstURL = images.appendingPathComponent("first.png")
    let secondURL = images.appendingPathComponent("second.png")
    try Data(repeating: 1, count: 700_000).write(to: firstURL)
    try Data(repeating: 2, count: 700_000).write(to: secondURL)

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    func imageEntry(_ url: URL, time: TimeInterval) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID().uuidString,
            content: .image(
                ImageClipboardContent(
                    thumbnailPath: url.path,
                    originalPath: nil,
                    sourceName: url.lastPathComponent,
                    width: 10,
                    height: 10,
                    ownsCachedFiles: true,
                    contentHash: ClipboardContent.sha256(Data(url.lastPathComponent.utf8))
                )
            ),
            copiedAt: Date(timeIntervalSince1970: time)
        )
    }
    let first = imageEntry(firstURL, time: 1)
    let second = imageEntry(secondURL, time: 2)
    _ = await store.upsert(first, retention: .forever, imageStorageLimitMB: 16)
    _ = await store.upsert(second, retention: .forever, imageStorageLimitMB: 16)
    let limited = try #require(await store.enforce(retention: .forever, imageStorageLimitMB: 1))

    #expect(!limited.contains { $0.id == first.id })
    #expect(limited.contains { $0.id == second.id })
    #expect(!FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
    await store.close()
}

@Test("Corrupt clipboard database is recreated")
func clipboardCorruptDatabaseRecovery() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("not a sqlite database".utf8).write(
        to: directory.appendingPathComponent("clipboard.sqlite3")
    )

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    let entry = textEntry("recovered")
    let snapshot = try #require(
        await store.upsert(entry, retention: .forever, imageStorageLimitMB: 16)
    )
    #expect(snapshot.contains { $0.id == entry.id })
    let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
    let preserved = try FileManager.default.contentsOfDirectory(
        at: recovery,
        includingPropertiesForKeys: nil
    )
    #expect(!preserved.isEmpty)
    await store.close()
}

@Test("Legacy transient clipboard cache is explicitly removed")
func clipboardLegacyCacheCleanup() async throws {
    let directory = try makeClipboardTestDirectory()
    let legacy = try makeClipboardTestDirectory()
    defer {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: legacy)
    }
    try Data([1, 2, 3]).write(to: legacy.appendingPathComponent("legacy-thumb.png"))
    let store = ClipboardHistoryStore(
        directory: directory,
        memoryWindow: 100,
        legacyCacheDirectory: legacy
    )
    let loaded = try #require(await store.load(retention: .forever, imageStorageLimitMB: 16))
    #expect(loaded.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    await store.close()
}

@Test("Non-corruption database open failures preserve existing paths")
func clipboardTransientDatabaseFailurePreservesHistory() async throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let databasePath = directory.appendingPathComponent("clipboard.sqlite3", isDirectory: true)
    try FileManager.default.createDirectory(at: databasePath, withIntermediateDirectories: true)

    let store = ClipboardHistoryStore(directory: directory, memoryWindow: 100)
    #expect(await store.load(retention: .forever, imageStorageLimitMB: 16) == nil)
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: databasePath.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
    await store.close()
}

@MainActor
@Test("Clipboard capture rejects sensitive pasteboard markers")
func clipboardSensitivePasteboardMarkers() {
    #expect(ClipboardStore.containsSensitiveType([.init("org.nspasteboard.ConcealedType")]))
    #expect(ClipboardStore.containsSensitiveType([.init("org.nspasteboard.TransientType")]))
    #expect(ClipboardStore.containsSensitiveType([.init("com.apple.is-sensitive")]))
    #expect(!ClipboardStore.containsSensitiveType([.string, .png]))
    #expect(!ClipboardStore.shouldCapture(types: [ClipboardStore.internalPasteboardType]))
    #expect(ClipboardStore.shouldCapture(types: [.string]))
    #expect(ClipboardStore.isSensitiveText("otpauth://totp/example"))
    #expect(ClipboardStore.isSensitiveText("OTPAUTH-MIGRATION://payload"))
    #expect(!ClipboardStore.isSensitiveText("ordinary clipboard text"))

    let oversized = String(repeating: "a", count: ClipboardStore.maxTextLength + 25)
    #expect(ClipboardStore.normalizedTextForCapture(oversized)?.count == ClipboardStore.maxTextLength)
    #expect(ClipboardStore.normalizedTextForCapture("  ordinary text  ") == "ordinary text")

    let item = NSPasteboardItem()
    let fileURL = URL(fileURLWithPath: "/tmp/meow-file-provider.txt")
    item.setString(
        fileURL.absoluteString,
        forType: NSPasteboard.PasteboardType("public.file-url")
    )
    #expect(ClipboardStore.fallbackFileURL(from: [item]) == fileURL)
}

@MainActor
@Test("Clipboard capture honors excluded application bundle identifiers")
func clipboardExcludedApplications() throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardStore(historyDirectory: directory)
    store.configure(
        retention: .threeMonths,
        imageStorageLimitMB: 512,
        disabledAppBundleIDs: ["Com.Example.PasswordManager"]
    )
    #expect(store.isExcludedApplication(bundleID: "com.example.passwordmanager"))
    #expect(!store.isExcludedApplication(bundleID: "com.example.editor"))
}

@MainActor
@Test("Clipboard image payload falls back to a valid thumbnail")
func clipboardImagePayloadFallback() throws {
    let directory = try makeClipboardTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let thumbnailURL = directory.appendingPathComponent("thumbnail.png")
    let missingOriginalURL = directory.appendingPathComponent("missing-original.png")
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )
    )
    bitmap.setColor(
        NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 1),
        atX: 0,
        y: 0
    )
    let pngData = try #require(bitmap.representation(using: .png, properties: [:]))
    try pngData.write(to: thumbnailURL)
    let content = ImageClipboardContent(
        thumbnailPath: thumbnailURL.path,
        originalPath: missingOriginalURL.path,
        sourceName: "fallback.png",
        width: 1,
        height: 1,
        ownsCachedFiles: false
    )

    let payload = try #require(ClipboardStore.pasteboardImagePayload(for: content))
    #expect(payload.originalURL == nil)
    #expect(NSImage(data: payload.tiffData) != nil)
}

@Test("Older settings receive safe clipboard defaults")
func clipboardSettingsCompatibility() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings.clipboardRetention == .threeMonths)
    #expect(settings.clipboardImageStorageLimitMB == 512)
    #expect(settings.clipboardDisabledAppBundleIDs.contains("com.apple.keychainaccess"))
    #expect(settings.clipboardDisabledAppBundleIDs.contains("com.apple.Passwords"))

    var customized = settings
    customized.clipboardRetention = .forever
    customized.clipboardImageStorageLimitMB = 1024
    customized.clipboardDisabledAppBundleIDs.append("com.example.password-manager")
    let decoded = try JSONDecoder().decode(
        AppSettings.self,
        from: JSONEncoder().encode(customized)
    )
    #expect(decoded.clipboardRetention == .forever)
    #expect(decoded.clipboardImageStorageLimitMB == 1024)
    #expect(decoded.clipboardDisabledAppBundleIDs.contains("com.example.password-manager"))

    let undersized = try JSONDecoder().decode(
        AppSettings.self,
        from: Data(#"{"clipboardImageStorageLimitMB":64}"#.utf8)
    )
    #expect(undersized.clipboardImageStorageLimitMB == 128)
}

@Test("Clipboard localization is complete in English and Simplified Chinese")
func clipboardLocalizationIsComplete() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Resources", isDirectory: true)
    let keys = [
        "launcher.section.clipboard.pinned",
        "clipboard.pin",
        "clipboard.unpin",
        "prefs.section.clipboard",
        "prefs.clipboard.retention.title",
        "prefs.clipboard.retention.subtitle",
        "clipboard.retention.forever",
        "prefs.clipboard.storage.limit.title",
        "prefs.clipboard.storage.title",
        "prefs.clipboard.excluded.apps.title",
        "prefs.clipboard.excluded.apps.add",
    ]

    for language in ["en", "zh-Hans"] {
        let url = sourceRoot
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let contents = try String(contentsOf: url, encoding: .utf8)
        for key in keys {
            #expect(contents.contains("\"\(key)\" ="))
        }
    }
}
