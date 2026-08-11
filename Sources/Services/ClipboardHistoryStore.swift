import Foundation
import GRDB

enum ClipboardStoragePaths {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meow/Clipboard", isDirectory: true)
    }

    static var legacyCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meow/Clipboard", isDirectory: true)
    }
}

/// GRDB-backed clipboard history. All database and cleanup work is isolated away from the main actor.
actor ClipboardHistoryStore {
    nonisolated let directoryURL: URL
    nonisolated let imagesDirectoryURL: URL
    nonisolated let pendingImagesDirectoryURL: URL

    private static let selectColumns = """
        id, kind, text_value, primary_path, secondary_path, display_name,
        width, height, duration, copied_at, source_bundle_id, pinned_at,
        content_hash, owns_files
        """

    private static let aliasedSelectColumns = """
        i.id, i.kind, i.text_value, i.primary_path, i.secondary_path, i.display_name,
        i.width, i.height, i.duration, i.copied_at, i.source_bundle_id, i.pinned_at,
        i.content_hash, i.owns_files
        """

    private static let schema = """
        CREATE TABLE IF NOT EXISTS clipboard_items(
          id TEXT NOT NULL UNIQUE,
          kind TEXT NOT NULL,
          text_value TEXT,
          primary_path TEXT,
          secondary_path TEXT,
          display_name TEXT,
          width INTEGER,
          height INTEGER,
          duration REAL,
          copied_at REAL NOT NULL,
          source_bundle_id TEXT,
          pinned_at REAL,
          content_hash TEXT NOT NULL UNIQUE,
          search_text TEXT NOT NULL,
          owns_files INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS clipboard_items_copied_at
          ON clipboard_items(copied_at DESC);
        CREATE INDEX IF NOT EXISTS clipboard_items_pinned_at
          ON clipboard_items(pinned_at) WHERE pinned_at IS NOT NULL;
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5(
          search_text,
          content='clipboard_items',
          content_rowid='rowid',
          tokenize='trigram'
        );
        CREATE TRIGGER IF NOT EXISTS clipboard_items_ai AFTER INSERT ON clipboard_items BEGIN
          INSERT INTO clipboard_items_fts(rowid, search_text) VALUES(new.rowid, new.search_text);
        END;
        CREATE TRIGGER IF NOT EXISTS clipboard_items_ad AFTER DELETE ON clipboard_items BEGIN
          INSERT INTO clipboard_items_fts(clipboard_items_fts, rowid, search_text)
          VALUES('delete', old.rowid, old.search_text);
        END;
        CREATE TRIGGER IF NOT EXISTS clipboard_items_au AFTER UPDATE OF search_text ON clipboard_items BEGIN
          INSERT INTO clipboard_items_fts(clipboard_items_fts, rowid, search_text)
          VALUES('delete', old.rowid, old.search_text);
          INSERT INTO clipboard_items_fts(rowid, search_text) VALUES(new.rowid, new.search_text);
        END;
        """

    private let memoryWindow: Int
    private let legacyCacheDirectory: URL?
    private var databaseQueue: DatabaseQueue?

    init(
        directory: URL? = nil,
        memoryWindow: Int = 1000,
        legacyCacheDirectory: URL? = nil
    ) {
        let directoryURL = directory ?? ClipboardStoragePaths.defaultDirectory
        self.directoryURL = directoryURL
        imagesDirectoryURL = directoryURL.appendingPathComponent("images", isDirectory: true)
        pendingImagesDirectoryURL = directoryURL.appendingPathComponent(
            "pending-images",
            isDirectory: true
        )
        self.memoryWindow = max(100, memoryWindow)
        self.legacyCacheDirectory = legacyCacheDirectory
            ?? (directory == nil ? ClipboardStoragePaths.legacyCacheDirectory : nil)

        try? FileManager.default.createDirectory(
            at: imagesDirectoryURL,
            withIntermediateDirectories: true
        )
        let databaseURL = directoryURL.appendingPathComponent("clipboard.sqlite3")
        do {
            databaseQueue = try Self.openDatabase(at: databaseURL)
        } catch {
            if Self.isCorruptDatabaseError(error),
               Self.quarantineDatabaseFiles(at: databaseURL)
            {
                databaseQueue = try? Self.openDatabase(at: databaseURL)
            } else {
                Self.logDatabaseOpenFailure(error)
                databaseQueue = nil
            }
        }
    }

    func load(
        retention: ClipboardRetention,
        imageStorageLimitMB: Int
    ) -> [ClipboardEntry]? {
        guard databaseQueue != nil else { return nil }
        removeLegacyCacheDirectoryIfNeeded()
        removeAbandonedPendingImages()
        enforceLimits(retention: retention, imageStorageLimitMB: imageStorageLimitMB)
        removeOrphanedImageFiles()
        return loadWindow()
    }

    func upsert(
        _ newEntry: ClipboardEntry,
        retention: ClipboardRetention,
        imageStorageLimitMB: Int
    ) -> [ClipboardEntry]? {
        guard let databaseQueue else { return nil }
        guard let materialized = materializePendingFiles(for: newEntry) else { return nil }
        let persistedEntry = materialized.entry

        let result: (existing: ClipboardEntry?, inserted: ClipboardEntry)
        do {
            result = try databaseQueue.write { database in
                let existing = try Self.entry(
                    withContentHash: persistedEntry.content.persistenceHash,
                    in: database
                )
                let entryToInsert: ClipboardEntry
                if let existing, existing.isPinned, !persistedEntry.isPinned {
                    entryToInsert = ClipboardEntry(
                        id: existing.id,
                        content: persistedEntry.content,
                        copiedAt: persistedEntry.copiedAt,
                        sourceBundleID: persistedEntry.sourceBundleID,
                        pinnedAt: existing.pinnedAt
                    )
                } else {
                    entryToInsert = persistedEntry
                }
                if let existing {
                    try database.execute(
                        sql: "DELETE FROM clipboard_items WHERE id = ?",
                        arguments: [existing.id]
                    )
                }
                try Self.insertRow(entryToInsert, in: database)
                return (existing, entryToInsert)
            }
        } catch {
            materialized.copiedPaths.forEach { try? FileManager.default.removeItem(atPath: $0) }
            return nil
        }

        materialized.pendingPaths.forEach { try? FileManager.default.removeItem(atPath: $0) }

        if let existing = result.existing {
            deleteOwnedFiles(for: existing, preserving: result.inserted)
        }
        enforceLimits(retention: retention, imageStorageLimitMB: imageStorageLimitMB)
        return loadWindow()
    }

    func remove(id: String) -> [ClipboardEntry]? {
        guard let databaseQueue else { return nil }
        let existing: ClipboardEntry?
        do {
            existing = try databaseQueue.write { database in
                let existing = try Self.entry(id: id, in: database)
                try database.execute(
                    sql: "DELETE FROM clipboard_items WHERE id = ?",
                    arguments: [id]
                )
                return existing
            }
        } catch {
            return nil
        }
        if let existing {
            deleteOwnedFiles(for: existing)
        }
        return loadWindow()
    }

    func remove(ids: Set<String>) -> [ClipboardEntry]? {
        guard let databaseQueue else { return nil }
        let existing: [ClipboardEntry]
        do {
            existing = try databaseQueue.write { database in
                var removed: [ClipboardEntry] = []
                for id in ids {
                    if let entry = try Self.entry(id: id, in: database) {
                        removed.append(entry)
                    }
                    try database.execute(
                        sql: "DELETE FROM clipboard_items WHERE id = ?",
                        arguments: [id]
                    )
                }
                return removed
            }
        } catch {
            return nil
        }
        existing.forEach { deleteOwnedFiles(for: $0) }
        return loadWindow()
    }

    func remove(contentHash: String) -> [ClipboardEntry]? {
        guard let databaseQueue else { return nil }
        let existing: ClipboardEntry?
        do {
            existing = try databaseQueue.write { database in
                let existing = try Self.entry(withContentHash: contentHash, in: database)
                try database.execute(
                    sql: "DELETE FROM clipboard_items WHERE content_hash = ?",
                    arguments: [contentHash]
                )
                return existing
            }
        } catch {
            return nil
        }
        if let existing {
            deleteOwnedFiles(for: existing)
        }
        return loadWindow()
    }

    func setPinned(id: String, pinned: Bool) -> [ClipboardEntry]? {
        guard let databaseQueue else { return nil }
        let sql = pinned
            ? "UPDATE clipboard_items SET pinned_at = ? WHERE id = ?"
            : "UPDATE clipboard_items SET pinned_at = NULL, copied_at = ? WHERE id = ?"
        do {
            try databaseQueue.write { database in
                try database.execute(
                    sql: sql,
                    arguments: [Date().timeIntervalSince1970, id]
                )
            }
        } catch {
            return nil
        }
        return loadWindow()
    }

    func search(_ query: String, limit: Int = 200) -> [ClipboardEntry]? {
        guard databaseQueue != nil else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return loadWindow() }

        let safeLimit = min(max(limit, 1), 500)
        let pinned = searchPinned(trimmed, limit: safeLimit)
        let pinnedIDs = Set(pinned.map(\.id))
        let regular = trimmed.count >= 3
            ? searchFTS(trimmed, limit: safeLimit)
            : searchLike(trimmed, limit: safeLimit)
        return Array((pinned + regular.filter { !pinnedIDs.contains($0.id) }).prefix(safeLimit))
    }

    func clearAll() -> [ClipboardEntry]? {
        guard let databaseQueue else { return nil }
        let existing: [ClipboardEntry]
        do {
            existing = try databaseQueue.write { database in
                let existing = try Self.entries(
                    in: database,
                    sql: "SELECT \(Self.selectColumns) FROM clipboard_items"
                )
                try database.execute(sql: "DELETE FROM clipboard_items")
                return existing
            }
        } catch {
            return nil
        }
        existing.forEach { deleteOwnedFiles(for: $0) }
        removeOrphanedImageFiles()
        _ = try? databaseQueue.writeWithoutTransaction { database in
            try database.checkpoint(.truncate)
        }
        return []
    }

    func enforce(
        retention: ClipboardRetention,
        imageStorageLimitMB: Int
    ) -> [ClipboardEntry]? {
        guard databaseQueue != nil else { return nil }
        enforceLimits(retention: retention, imageStorageLimitMB: imageStorageLimitMB)
        removeOrphanedImageFiles()
        return loadWindow()
    }

    func storageUsageBytes() -> Int64 {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    func close() {
        databaseQueue = nil
    }

    // MARK: - Limits

    private func enforceLimits(retention: ClipboardRetention, imageStorageLimitMB: Int) {
        if let cutoff = retention.cutoffDate, let databaseQueue {
            let stale: [ClipboardEntry]
            do {
                stale = try databaseQueue.write { database in
                    let stale = try Self.entries(
                        in: database,
                        sql: """
                            SELECT \(Self.selectColumns) FROM clipboard_items
                            WHERE pinned_at IS NULL AND copied_at < ?
                            """,
                        arguments: [cutoff.timeIntervalSince1970]
                    )
                    try database.execute(
                        sql: "DELETE FROM clipboard_items WHERE pinned_at IS NULL AND copied_at < ?",
                        arguments: [cutoff.timeIntervalSince1970]
                    )
                    return stale
                }
            } catch {
                stale = []
            }
            stale.forEach { deleteOwnedFiles(for: $0) }
        }

        pruneImages(toLimitMB: imageStorageLimitMB)
    }

    private func pruneImages(toLimitMB limitMB: Int) {
        let limitBytes = Int64(max(1, limitMB)) * 1_024 * 1_024
        var usage = ownedImageUsageBytes()
        guard usage > limitBytes else { return }

        let candidates = entries(
            sql: """
                SELECT \(Self.selectColumns) FROM clipboard_items
                WHERE kind = 'image' AND pinned_at IS NULL AND owns_files = 1
                ORDER BY copied_at ASC
                """
        )
        for entry in candidates where usage > limitBytes {
            usage -= ownedFileSize(for: entry)
            guard deleteRow(id: entry.id) else { continue }
            deleteOwnedFiles(for: entry)
        }
    }

    private func ownedImageUsageBytes() -> Int64 {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(
            at: imagesDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func ownedFileSize(for entry: ClipboardEntry) -> Int64 {
        ownedPaths(for: entry).reduce(into: Int64(0)) { total, path in
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    // MARK: - Queries

    private func loadWindow() -> [ClipboardEntry] {
        let pinned = entries(
            sql: """
                SELECT \(Self.selectColumns) FROM clipboard_items
                WHERE pinned_at IS NOT NULL
                ORDER BY pinned_at DESC
                """
        )
        let regular = entries(
            sql: """
                SELECT \(Self.selectColumns) FROM clipboard_items
                WHERE pinned_at IS NULL
                ORDER BY copied_at DESC LIMIT ?
                """,
            arguments: [memoryWindow]
        )
        return pinned + regular
    }

    private func searchPinned(_ query: String, limit: Int) -> [ClipboardEntry] {
        let escapedQuery = Self.escapeLikeQuery(query)
        return entries(
            sql: """
                SELECT \(Self.selectColumns) FROM clipboard_items
                WHERE pinned_at IS NOT NULL
                  AND search_text LIKE '%' || ? || '%' ESCAPE '!' COLLATE NOCASE
                ORDER BY pinned_at DESC LIMIT ?
                """,
            arguments: [escapedQuery, limit]
        )
    }

    private func searchLike(_ query: String, limit: Int) -> [ClipboardEntry] {
        let escapedQuery = Self.escapeLikeQuery(query)
        return entries(
            sql: """
                SELECT \(Self.selectColumns) FROM clipboard_items
                WHERE search_text LIKE '%' || ? || '%' ESCAPE '!' COLLATE NOCASE
                ORDER BY copied_at DESC LIMIT ?
                """,
            arguments: [escapedQuery, limit]
        )
    }

    private static func escapeLikeQuery(_ query: String) -> String {
        query.replacingOccurrences(of: "!", with: "!!")
            .replacingOccurrences(of: "%", with: "!%")
            .replacingOccurrences(of: "_", with: "!_")
    }

    private func searchFTS(_ query: String, limit: Int) -> [ClipboardEntry] {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let match = "\"\(escaped)\""
        return entries(
            sql: """
                SELECT \(Self.aliasedSelectColumns)
                FROM clipboard_items_fts f
                JOIN clipboard_items i ON i.rowid = f.rowid
                WHERE clipboard_items_fts MATCH ?
                ORDER BY i.copied_at DESC LIMIT ?
                """,
            arguments: [match, limit]
        )
    }

    private func entries(
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) -> [ClipboardEntry] {
        guard let databaseQueue else { return [] }
        return (try? databaseQueue.read { database in
            try Self.entries(in: database, sql: sql, arguments: arguments)
        }) ?? []
    }

    private static func entries(
        in database: Database,
        sql: String,
        arguments: StatementArguments = StatementArguments()
    ) throws -> [ClipboardEntry] {
        try Row.fetchAll(database, sql: sql, arguments: arguments).compactMap(decodeRow)
    }

    private static func entry(id: String, in database: Database) throws -> ClipboardEntry? {
        try entries(
            in: database,
            sql: "SELECT \(selectColumns) FROM clipboard_items WHERE id = ? LIMIT 1",
            arguments: [id]
        ).first
    }

    private static func entry(
        withContentHash contentHash: String,
        in database: Database
    ) throws -> ClipboardEntry? {
        try entries(
            in: database,
            sql: "SELECT \(selectColumns) FROM clipboard_items WHERE content_hash = ? LIMIT 1",
            arguments: [contentHash]
        ).first
    }

    // MARK: - Mutations

    private static func insertRow(_ entry: ClipboardEntry, in database: Database) throws {
        let values = persistenceValues(for: entry)
        let arguments: StatementArguments = [
            entry.id,
            values.kind,
            values.text,
            values.primaryPath,
            values.secondaryPath,
            values.displayName,
            values.width,
            values.height,
            values.duration,
            entry.copiedAt.timeIntervalSince1970,
            entry.sourceBundleID,
            entry.pinnedAt?.timeIntervalSince1970,
            entry.content.persistenceHash,
            entry.content.searchText,
            values.ownsFiles,
        ]
        try database.execute(
            sql: """
                INSERT INTO clipboard_items(
                  id, kind, text_value, primary_path, secondary_path, display_name,
                  width, height, duration, copied_at, source_bundle_id, pinned_at,
                  content_hash, search_text, owns_files
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            arguments: arguments
        )
    }

    @discardableResult
    private func deleteRow(id: String) -> Bool {
        guard let databaseQueue else { return false }
        do {
            try databaseQueue.write { database in
                try database.execute(
                    sql: "DELETE FROM clipboard_items WHERE id = ?",
                    arguments: [id]
                )
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Files

    private struct MaterializedEntry {
        let entry: ClipboardEntry
        let pendingPaths: [String]
        let copiedPaths: [String]
    }

    private func materializePendingFiles(for entry: ClipboardEntry) -> MaterializedEntry? {
        guard case let .image(image) = entry.content, image.ownsCachedFiles else {
            return MaterializedEntry(entry: entry, pendingPaths: [], copiedPaths: [])
        }

        var pendingPaths: [String] = []
        var copiedPaths: [String] = []
        func materialize(_ path: String) -> String? {
            guard isInside(path, directory: pendingImagesDirectoryURL) else { return path }
            let source = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: source.path) else { return nil }
            var destination = imagesDirectoryURL.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = imagesDirectoryURL.appendingPathComponent(
                    "\(UUID().uuidString.lowercased())-\(source.lastPathComponent)"
                )
            }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                pendingPaths.append(source.path)
                copiedPaths.append(destination.path)
                return destination.path
            } catch {
                return nil
            }
        }

        guard let thumbnailPath = materialize(image.thumbnailPath) else {
            copiedPaths.forEach { try? FileManager.default.removeItem(atPath: $0) }
            return nil
        }
        let originalPath: String?
        if let path = image.originalPath {
            guard let materializedPath = materialize(path) else {
                copiedPaths.forEach { try? FileManager.default.removeItem(atPath: $0) }
                return nil
            }
            originalPath = materializedPath
        } else {
            originalPath = nil
        }

        let content = ImageClipboardContent(
            thumbnailPath: thumbnailPath,
            originalPath: originalPath,
            sourceName: image.sourceName,
            width: image.width,
            height: image.height,
            ownsCachedFiles: true,
            contentHash: image.contentHash
        )
        return MaterializedEntry(
            entry: ClipboardEntry(
                id: entry.id,
                content: .image(content),
                copiedAt: entry.copiedAt,
                sourceBundleID: entry.sourceBundleID,
                pinnedAt: entry.pinnedAt
            ),
            pendingPaths: pendingPaths,
            copiedPaths: copiedPaths
        )
    }

    /// Pre-persistence clipboard images from previous builds were transient cache only.
    private func removeLegacyCacheDirectoryIfNeeded() {
        guard let legacyCacheDirectory,
              legacyCacheDirectory.standardizedFileURL != directoryURL.standardizedFileURL,
              FileManager.default.fileExists(atPath: legacyCacheDirectory.path)
        else { return }
        try? FileManager.default.removeItem(at: legacyCacheDirectory)
    }

    private func removeAbandonedPendingImages() {
        let expiration = Date().addingTimeInterval(-86_400)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: pendingImagesDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files {
            let modified = try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if (modified ?? .distantPast) < expiration {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func removeOrphanedImageFiles() {
        guard let databaseQueue else { return }
        let referenced: Set<String>
        do {
            let referencedPaths = try databaseQueue.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                        SELECT primary_path, secondary_path FROM clipboard_items
                        WHERE kind = 'image' AND owns_files = 1
                        """
                )
                return Set(rows.flatMap { row -> [String] in
                    let primaryPath: String? = row["primary_path"]
                    let secondaryPath: String? = row["secondary_path"]
                    return [primaryPath, secondaryPath].compactMap { $0 }
                })
            }
            referenced = Set(referencedPaths.map(canonicalPath))
        } catch {
            return
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: imagesDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where !referenced.contains(canonicalPath(file.path)) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func deleteOwnedFiles(
        for entry: ClipboardEntry,
        preserving replacement: ClipboardEntry? = nil
    ) {
        let preserved = Set(replacement.map(ownedPaths) ?? [])
        for path in ownedPaths(for: entry) where !preserved.contains(path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func ownedPaths(for entry: ClipboardEntry) -> [String] {
        switch entry.content {
        case let .image(image) where image.ownsCachedFiles:
            return [image.thumbnailPath, image.originalPath].compactMap { path in
                guard let path, owns(path) else { return nil }
                return path
            }
        case let .audio(audio) where audio.ownsCachedFile:
            return [audio.cachePath]
        default:
            return []
        }
    }

    private func owns(_ path: String) -> Bool {
        isInside(path, directory: imagesDirectoryURL)
    }

    private func isInside(_ path: String, directory: URL) -> Bool {
        canonicalPath(path).hasPrefix(canonicalPath(directory.path) + "/")
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: - GRDB helpers

    private static func openDatabase(at url: URL) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.foreignKeysEnabled = true

        let databaseQueue = try DatabaseQueue(path: url.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("clipboardHistory.v1") { database in
            try database.execute(sql: schema)
        }
        try migrator.migrate(databaseQueue)
        return databaseQueue
    }

    private static func isCorruptDatabaseError(_ error: Error) -> Bool {
        guard let databaseError = error as? DatabaseError else { return false }
        let code = databaseError.resultCode
        return code == .SQLITE_CORRUPT || code == .SQLITE_NOTADB
    }

    private static func quarantineDatabaseFiles(at url: URL) -> Bool {
        let fileManager = FileManager.default
        let basePath = url.path
        guard fileManager.fileExists(atPath: basePath) else { return false }
        let recoveryDirectory = url.deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(
                "clipboard-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        do {
            try fileManager.createDirectory(
                at: recoveryDirectory,
                withIntermediateDirectories: true
            )
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: basePath + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(
                    at: source,
                    to: recoveryDirectory.appendingPathComponent(source.lastPathComponent)
                )
            }
            NSLog("[Meow Clipboard] Preserved a corrupt history database for recovery")
            return true
        } catch {
            NSLog("[Meow Clipboard] Could not preserve the corrupt history database")
            return false
        }
    }

    private static func logDatabaseOpenFailure(_ error: Error) {
        if let databaseError = error as? DatabaseError {
            NSLog(
                "[Meow Clipboard] History database unavailable (SQLite code %d); existing files were preserved",
                databaseError.resultCode.rawValue
            )
        } else {
            NSLog("[Meow Clipboard] History database unavailable; existing files were preserved")
        }
    }

    private struct PersistenceValues {
        let kind: String
        let text: String?
        let primaryPath: String?
        let secondaryPath: String?
        let displayName: String?
        let width: Int?
        let height: Int?
        let duration: Double?
        let ownsFiles: Bool
    }

    private static func persistenceValues(for entry: ClipboardEntry) -> PersistenceValues {
        switch entry.content {
        case let .text(text):
            return PersistenceValues(
                kind: "text", text: text, primaryPath: nil, secondaryPath: nil,
                displayName: nil, width: nil, height: nil, duration: nil, ownsFiles: false
            )
        case let .url(url):
            return PersistenceValues(
                kind: "url", text: url.absoluteString, primaryPath: nil, secondaryPath: nil,
                displayName: nil, width: nil, height: nil, duration: nil, ownsFiles: false
            )
        case let .file(file):
            return PersistenceValues(
                kind: "file", text: nil, primaryPath: file.url.path, secondaryPath: nil,
                displayName: file.name, width: nil, height: nil, duration: nil, ownsFiles: false
            )
        case let .image(image):
            return PersistenceValues(
                kind: "image", text: nil, primaryPath: image.thumbnailPath,
                secondaryPath: image.originalPath, displayName: image.sourceName,
                width: image.width, height: image.height, duration: nil,
                ownsFiles: image.ownsCachedFiles
            )
        case let .audio(audio):
            return PersistenceValues(
                kind: "audio", text: nil, primaryPath: audio.cachePath, secondaryPath: nil,
                displayName: audio.name, width: nil, height: nil, duration: audio.duration,
                ownsFiles: audio.ownsCachedFile
            )
        }
    }

    private static func decodeRow(_ row: Row) -> ClipboardEntry? {
        let id: String = row["id"]
        let kind: String = row["kind"]
        let contentHash: String = row["content_hash"]
        let content: ClipboardContent

        switch kind {
        case "text":
            guard let text: String = row["text_value"] else { return nil }
            content = .text(text)
        case "url":
            guard let value: String = row["text_value"], let url = URL(string: value) else {
                return nil
            }
            content = .url(url)
        case "file":
            guard let path: String = row["primary_path"] else { return nil }
            let url = URL(fileURLWithPath: path)
            let displayName: String? = row["display_name"]
            content = .file(
                FileClipboardContent(url: url, name: displayName ?? url.lastPathComponent)
            )
        case "image":
            guard let thumbnailPath: String = row["primary_path"] else { return nil }
            let originalPath: String? = row["secondary_path"]
            let sourceName: String? = row["display_name"]
            let width: Int? = row["width"]
            let height: Int? = row["height"]
            let ownsFiles: Bool = row["owns_files"]
            content = .image(
                ImageClipboardContent(
                    thumbnailPath: thumbnailPath,
                    originalPath: originalPath,
                    sourceName: sourceName ?? "ClipboardImage",
                    width: width ?? 0,
                    height: height ?? 0,
                    ownsCachedFiles: ownsFiles,
                    contentHash: contentHash
                )
            )
        case "audio":
            guard let path: String = row["primary_path"] else { return nil }
            let displayName: String? = row["display_name"]
            let duration: Double? = row["duration"]
            let ownsFiles: Bool = row["owns_files"]
            content = .audio(
                AudioClipboardContent(
                    cachePath: path,
                    name: displayName ?? URL(fileURLWithPath: path).lastPathComponent,
                    duration: duration,
                    ownsCachedFile: ownsFiles
                )
            )
        default:
            return nil
        }

        let copiedAt: Double = row["copied_at"]
        let sourceBundleID: String? = row["source_bundle_id"]
        let pinnedAt: Double? = row["pinned_at"]
        return ClipboardEntry(
            id: id,
            content: content,
            copiedAt: Date(timeIntervalSince1970: copiedAt),
            sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}
