import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ClipboardImageCache: @unchecked Sendable {
    static let shared = ClipboardImageCache()

    private let pendingImagesDirectory: URL
    private let maxImageDimension = 4096
    private let maxOriginalBytes = 64 * 1_024 * 1_024

    private init(directory: URL = ClipboardStoragePaths.defaultDirectory) {
        pendingImagesDirectory = directory.appendingPathComponent("pending-images", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: pendingImagesDirectory,
            withIntermediateDirectories: true
        )
    }

    func saveImageData(
        _ data: Data,
        sourceName: String = "Screenshot",
        preserveOriginalFormat: Bool = false
    ) -> ImageClipboardContent? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions
        ), let thumbnailData = pngData(for: thumbnail)
        else { return nil }

        let fileURLs = makeImageFileURLs(
            sourceName: sourceName,
            fallbackExtension: preserveOriginalFormat ? nil : "png"
        )
        do {
            try thumbnailData.write(to: fileURLs.thumbnail, options: .atomic)
        } catch {
            return nil
        }

        let canStoreOriginal = width <= maxImageDimension
            && height <= maxImageDimension
            && data.count <= maxOriginalBytes
        var originalPath: String?
        if canStoreOriginal {
            let originalData = preserveOriginalFormat ? data : (pngData(for: cgImage) ?? data)
            do {
                try originalData.write(to: fileURLs.original, options: .atomic)
                originalPath = fileURLs.original.path
            } catch {
                originalPath = nil
            }
        }

        return ImageClipboardContent(
            thumbnailPath: fileURLs.thumbnail.path,
            originalPath: originalPath,
            sourceName: sourceName,
            width: width,
            height: height,
            contentHash: ClipboardContent.sha256(data)
        )
    }

    private func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func makeImageFileURLs(
        sourceName: String,
        fallbackExtension: String?
    ) -> (original: URL, thumbnail: URL) {
        let sourceURL = URL(fileURLWithPath: sourceName)
        let candidate = sourceURL.deletingPathExtension().lastPathComponent
        let baseName = sanitizeFileName(candidate).isEmpty
            ? "ClipboardImage"
            : sanitizeFileName(candidate)
        let sourceExtension = sanitizeFileExtension(sourceURL.pathExtension)
        let resolvedExtension = sourceExtension.isEmpty ? fallbackExtension : sourceExtension
        let suffix = UUID().uuidString.lowercased()
        let originalName = resolvedExtension.map { "\(baseName)-\(suffix).\($0)" }
            ?? "\(baseName)-\(suffix)"
        return (
            pendingImagesDirectory.appendingPathComponent(originalName),
            pendingImagesDirectory.appendingPathComponent("\(baseName)-\(suffix)_thumb.png")
        )
    }

    private func sanitizeFileName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeFileExtension(_ value: String) -> String {
        value.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: "",
            options: .regularExpression
        ).lowercased()
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    func resized(toFit boundingSize: NSSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return self }
        let scale = min(boundingSize.width / size.width, boundingSize.height / size.height, 1)
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    func resized(to boundingSize: NSSize) -> NSImage {
        resized(toFit: boundingSize)
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    private struct PasteboardItemSnapshot {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    static let internalPasteboardType = NSPasteboard.PasteboardType("tech.lury.meow.internal")
    static let sensitivePasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive"),
    ]
    static let maxTextLength = 100_000
    static let maxImageSourceBytes = 64 * 1_024 * 1_024

    @Published private(set) var storageUsageBytes: Int64 = 0

    private let historyStore: ClipboardHistoryStore
    private let memoryWindow: Int
    private var entries: [ClipboardEntry] = []
    private var lastChangeCount = 0
    private var monitorTimer: Timer?
    private var workspaceApplicationObserver: NSObjectProtocol?
    private var onChange: (() -> Void)?
    private var persistenceTask: Task<Void, Never>?
    private var storageUsageRefreshTask: Task<Void, Never>?
    private var mutationRevision: UInt64 = 0
    private var captureGeneration: UInt64 = 0
    private var isMonitoring = false
    private var hasLoadedHistory = false
    private var pendingLimitEnforcement = false
    private var retention: ClipboardRetention = .threeMonths
    private var imageStorageLimitMB = 512
    private var disabledBundleIDs: Set<String> = []

    init(
        historyDirectory: URL? = nil,
        memoryWindow: Int = 1000,
        legacyCacheDirectory: URL? = nil
    ) {
        self.memoryWindow = max(100, memoryWindow)
        historyStore = ClipboardHistoryStore(
            directory: historyDirectory,
            memoryWindow: memoryWindow,
            legacyCacheDirectory: legacyCacheDirectory
        )
    }

    var storageDirectoryURL: URL {
        historyStore.directoryURL
    }

    func configure(
        retention: ClipboardRetention,
        imageStorageLimitMB: Int,
        disabledAppBundleIDs: [String]
    ) {
        let normalizedLimit = max(128, imageStorageLimitMB)
        let limitsChanged = self.retention != retention
            || self.imageStorageLimitMB != normalizedLimit
        self.retention = retention
        self.imageStorageLimitMB = normalizedLimit
        let normalizedDisabledBundleIDs = Set(disabledAppBundleIDs.map { $0.lowercased() })
        if disabledBundleIDs != normalizedDisabledBundleIDs {
            invalidatePendingCaptures()
        }
        disabledBundleIDs = normalizedDisabledBundleIDs

        if limitsChanged {
            if hasLoadedHistory {
                enqueueLimitEnforcement()
            } else {
                pendingLimitEnforcement = true
            }
        }
    }

    func startMonitoring(onChange: @escaping () -> Void) {
        stopMonitoring()
        self.onChange = onChange
        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount
        if !hasLoadedHistory {
            reloadHistory()
        }

        workspaceApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.checkClipboard(sourceBundleID: bundleID)
            }
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    func stopMonitoring() {
        isMonitoring = false
        invalidatePendingCaptures()
        monitorTimer?.invalidate()
        monitorTimer = nil
        if let workspaceApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceApplicationObserver)
            self.workspaceApplicationObserver = nil
        }
    }

    func getEntries() -> [ClipboardEntry] {
        entries
    }

    func search(_ query: String, limit: Int = 200) async -> [ClipboardEntry] {
        await waitForPendingPersistence()
        guard !Task.isCancelled else { return [] }
        if let result = await historyStore.search(query, limit: limit) {
            return result
        }
        return entries.filter { $0.content.searchText.localizedCaseInsensitiveContains(query) }
    }

    func waitForPendingPersistence() async {
        await persistenceTask?.value
    }

    func insertCapture(_ artifact: CaptureArtifact) {
        let imageContent = ImageClipboardContent(
            thumbnailPath: artifact.thumbnailURL.path,
            originalPath: artifact.imageURL.path,
            sourceName: L10n.screenshotClipboardName,
            width: artifact.width,
            height: artifact.height,
            ownsCachedFiles: false
        )
        addEntry(
            ClipboardEntry(
                id: artifact.id.uuidString,
                content: .image(imageContent),
                copiedAt: artifact.createdAt,
                sourceBundleID: Bundle.main.bundleIdentifier
            )
        )
    }

    func removeCaptureEntries(ids: Set<UUID>) {
        let idStrings = Set(ids.map(\.uuidString))
        entries.removeAll { idStrings.contains($0.id) }
        let revision = recordLocalMutation()
        enqueuePersistence(snapshotRevision: revision) { historyStore in
            await historyStore.remove(ids: idStrings)
        }
        notifyChanged()
    }

    func writeCaptureToPasteboard(_ artifact: CaptureArtifact) {
        if artifact.kind == .scrolling {
            writeScrollingCaptureToPasteboard(artifact)
            return
        }
        guard let image = NSImage(contentsOf: artifact.imageURL),
              let tiffData = image.tiffRepresentation
        else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        pasteboard.writeObjects([artifact.imageURL as NSURL])
        markInternalWrite(on: pasteboard)
    }

    private func writeScrollingCaptureToPasteboard(_ artifact: CaptureArtifact) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let pngData = try? Data(contentsOf: artifact.imageURL, options: .mappedIfSafe) {
            pasteboard.setData(pngData, forType: .png)
        }
        pasteboard.writeObjects([artifact.imageURL as NSURL])
        markInternalWrite(on: pasteboard)
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        let revision = recordLocalMutation()
        enqueuePersistence(snapshotRevision: revision) { historyStore in
            await historyStore.remove(id: entry.id)
        }
        notifyChanged()
    }

    func clearAll() {
        invalidatePendingCaptures()
        entries.removeAll()
        let revision = recordLocalMutation()
        enqueuePersistence(snapshotRevision: revision) { historyStore in
            await historyStore.clearAll()
        }
        notifyChanged()
    }

    func togglePinned(_ entry: ClipboardEntry) {
        let updated = entry.isPinned
            ? entry.with(copiedAt: Date(), pinnedAt: nil)
            : entry.with(pinnedAt: Date())
        entries.removeAll { $0.id == entry.id }
        entries.append(updated)
        entries = Self.trimmedDisplayOrder(entries, memoryWindow: memoryWindow)
        let revision = recordLocalMutation()
        enqueuePersistence(snapshotRevision: revision) { historyStore in
            await historyStore.setPinned(id: entry.id, pinned: !entry.isPinned)
        }
        notifyChanged()
    }

    func writeToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general

        switch entry.content {
        case let .text(string):
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        case let .url(url):
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.writeObjects([url as NSURL])
        case let .file(fileContent):
            pasteboard.clearContents()
            pasteboard.writeObjects([fileContent.url as NSURL])
        case let .image(imageContent):
            guard let payload = Self.pasteboardImagePayload(for: imageContent) else { return }
            pasteboard.clearContents()
            pasteboard.setData(payload.tiffData, forType: .tiff)
            if let originalURL = payload.originalURL {
                pasteboard.writeObjects([originalURL as NSURL])
            }
        case let .audio(audioContent):
            pasteboard.clearContents()
            pasteboard.writeObjects([URL(fileURLWithPath: audioContent.cachePath) as NSURL])
        }

        markInternalWrite(on: pasteboard)
    }

    static func pasteboardImagePayload(
        for imageContent: ImageClipboardContent
    ) -> (tiffData: Data, originalURL: URL?)? {
        if let originalPath = imageContent.originalPath,
           let image = NSImage(contentsOfFile: originalPath),
           let tiffData = image.tiffRepresentation
        {
            return (tiffData, URL(fileURLWithPath: originalPath))
        }
        guard let thumbnail = NSImage(contentsOfFile: imageContent.thumbnailPath),
              let tiffData = thumbnail.tiffRepresentation
        else { return nil }
        return (tiffData, nil)
    }

    func writePrivateTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markInternalWrite(on: pasteboard)
    }

    func removePrivateTextFromHistory(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = ClipboardContent.text(normalized)
        entries.removeAll { $0.content == content }
        let revision = recordLocalMutation()
        let hash = content.persistenceHash
        enqueuePersistence(snapshotRevision: revision) { historyStore in
            await historyStore.remove(contentHash: hash)
        }
        notifyChanged()
    }

    /// Pastes text into the focused app without adding the temporary text to clipboard history.
    /// When Accessibility permission is unavailable, the text remains on the clipboard.
    func performTemporaryTextPaste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshots = pasteboard.pasteboardItems?.compactMap { item -> PasteboardItemSnapshot? in
            let values = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return values.isEmpty ? nil : PasteboardItemSnapshot(values: values)
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markInternalWrite(on: pasteboard)
        let temporaryChangeCount = pasteboard.changeCount

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard pasteboard.changeCount == temporaryChangeCount else {
                self?.lastChangeCount = pasteboard.changeCount
                return
            }
            let restoredItems = snapshots.map { snapshot in
                let item = NSPasteboardItem()
                for value in snapshot.values {
                    item.setData(value.data, forType: value.type)
                }
                return item
            }
            pasteboard.clearContents()
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
            self?.lastChangeCount = pasteboard.changeCount
        }
        return true
    }

    static func containsSensitiveType(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        !Set(types).isDisjoint(with: sensitivePasteboardTypes)
    }

    static func shouldCapture(types: [NSPasteboard.PasteboardType]) -> Bool {
        !types.contains(internalPasteboardType) && !containsSensitiveType(types)
    }

    static func isSensitiveText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.hasPrefix("otpauth://")
            || lowercased.hasPrefix("otpauth-migration://")
    }

    static func normalizedTextForCapture(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSensitiveText(trimmed) else { return nil }
        return trimmed.count > maxTextLength
            ? String(trimmed.prefix(maxTextLength))
            : trimmed
    }

    static func fallbackFileURL(from items: [NSPasteboardItem]) -> URL? {
        let type = NSPasteboard.PasteboardType("public.file-url")
        for item in items {
            guard let data = item.data(forType: type),
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: value)
            else { continue }
            return url
        }
        return nil
    }

    func isExcludedApplication(bundleID: String) -> Bool {
        disabledBundleIDs.contains(bundleID.lowercased())
    }

    // MARK: - Monitoring

    private func checkClipboard(sourceBundleID sourceBundleIDOverride: String? = nil) {
        guard isMonitoring else { return }
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let types = pasteboard.types ?? []
        guard Self.shouldCapture(types: types) else { return }

        let sourceBundleID = sourceBundleIDOverride
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, disabledBundleIDs.contains(sourceBundleID.lowercased()) {
            return
        }
        let captureGeneration = captureGeneration

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first
        {
            captureURL(
                firstURL,
                sourceBundleID: sourceBundleID,
                observedChangeCount: currentCount,
                captureGeneration: captureGeneration
            )
            return
        }

        if let fallbackURL = Self.fallbackFileURL(from: pasteboard.pasteboardItems ?? []) {
            captureURL(
                fallbackURL,
                sourceBundleID: sourceBundleID,
                observedChangeCount: currentCount,
                captureGeneration: captureGeneration
            )
            return
        }

        if let type = pasteboard.availableType(from: [.png, .tiff]),
           let data = pasteboard.data(forType: type)
        {
            addImageDataEntryAsync(
                data: data,
                sourceName: "Screenshot.png",
                sourceBundleID: sourceBundleID,
                observedChangeCount: currentCount,
                captureGeneration: captureGeneration,
                preserveOriginalFormat: type == .png
            )
            return
        }

        if let text = pasteboard.string(forType: .string) {
            guard let content = Self.normalizedTextForCapture(text) else { return }
            addEntry(
                ClipboardEntry(
                    id: UUID().uuidString,
                    content: .text(content),
                    copiedAt: Date(),
                    sourceBundleID: sourceBundleID
                )
            )
        }
    }

    private func captureURL(
        _ url: URL,
        sourceBundleID: String?,
        observedChangeCount: Int,
        captureGeneration: UInt64
    ) {
        if url.scheme == "http" || url.scheme == "https" {
            addEntry(
                ClipboardEntry(
                    id: UUID().uuidString,
                    content: .url(url),
                    copiedAt: Date(),
                    sourceBundleID: sourceBundleID
                )
            )
            return
        }

        let imageExtensions = Set(["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp", "ico"])
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            addImageFileEntryAsync(
                url: url,
                sourceBundleID: sourceBundleID,
                observedChangeCount: observedChangeCount,
                captureGeneration: captureGeneration
            )
        } else {
            addFileEntry(url: url, sourceBundleID: sourceBundleID)
        }
    }

    private func addImageFileEntryAsync(
        url: URL,
        sourceBundleID: String?,
        observedChangeCount: Int,
        captureGeneration: UInt64
    ) {
        let maximumSourceBytes = Self.maxImageSourceBytes
        Task.detached(priority: .utility) { [weak self] in
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard fileSize <= maximumSourceBytes,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let imageContent = ClipboardImageCache.shared.saveImageData(
                    data,
                    sourceName: url.lastPathComponent,
                    preserveOriginalFormat: true
                  )
            else {
                await self?.addFileEntryIfCurrent(
                    url: url,
                    sourceBundleID: sourceBundleID,
                    observedChangeCount: observedChangeCount,
                    captureGeneration: captureGeneration
                )
                return
            }
            await self?.addImageEntryIfCurrent(
                imageContent,
                sourceBundleID: sourceBundleID,
                observedChangeCount: observedChangeCount,
                captureGeneration: captureGeneration
            )
        }
    }

    private func addImageDataEntryAsync(
        data: Data,
        sourceName: String,
        sourceBundleID: String?,
        observedChangeCount: Int,
        captureGeneration: UInt64,
        preserveOriginalFormat: Bool
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let imageContent = ClipboardImageCache.shared.saveImageData(
                data,
                sourceName: sourceName,
                preserveOriginalFormat: preserveOriginalFormat
            ) else { return }
            await self?.addImageEntryIfCurrent(
                imageContent,
                sourceBundleID: sourceBundleID,
                observedChangeCount: observedChangeCount,
                captureGeneration: captureGeneration
            )
        }
    }

    private func addImageEntryIfCurrent(
        _ imageContent: ImageClipboardContent,
        sourceBundleID: String?,
        observedChangeCount: Int,
        captureGeneration: UInt64
    ) {
        guard isMonitoring,
              self.captureGeneration == captureGeneration,
              lastChangeCount == observedChangeCount
        else {
            cleanupUnpersistedImage(imageContent)
            return
        }
        addEntry(
            ClipboardEntry(
                id: UUID().uuidString,
                content: .image(imageContent),
                copiedAt: Date(),
                sourceBundleID: sourceBundleID
            )
        )
    }

    private func addFileEntryIfCurrent(
        url: URL,
        sourceBundleID: String?,
        observedChangeCount: Int,
        captureGeneration: UInt64
    ) {
        guard isMonitoring,
              self.captureGeneration == captureGeneration,
              lastChangeCount == observedChangeCount
        else { return }
        addFileEntry(url: url, sourceBundleID: sourceBundleID)
    }

    private func addFileEntry(url: URL, sourceBundleID: String?) {
        addEntry(
            ClipboardEntry(
                id: UUID().uuidString,
                content: .file(FileClipboardContent(url: url, name: url.lastPathComponent)),
                copiedAt: Date(),
                sourceBundleID: sourceBundleID
            )
        )
    }

    // MARK: - Persistence bridge

    private func addEntry(_ newEntry: ClipboardEntry) {
        var entry = newEntry
        if let existing = entries.first(where: { $0.content.persistenceHash == newEntry.content.persistenceHash }) {
            entry = ClipboardEntry(
                id: existing.id,
                content: newEntry.content,
                copiedAt: newEntry.copiedAt,
                sourceBundleID: newEntry.sourceBundleID,
                pinnedAt: existing.pinnedAt
            )
        }
        entries.removeAll { $0.id == entry.id || $0.content.persistenceHash == entry.content.persistenceHash }
        entries.append(entry)
        entries = Self.trimmedDisplayOrder(entries, memoryWindow: memoryWindow)
        let revision = recordLocalMutation()

        let retention = retention
        let imageLimit = imageStorageLimitMB
        let persistedEntry = entry
        enqueuePersistence(snapshotRevision: revision) { historyStore in
            await historyStore.upsert(
                persistedEntry,
                retention: retention,
                imageStorageLimitMB: imageLimit
            )
        }
        notifyChanged()
    }

    private func reloadHistory() {
        let retention = retention
        let imageLimit = imageStorageLimitMB
        enqueuePersistence { historyStore in
            await historyStore.load(
                retention: retention,
                imageStorageLimitMB: imageLimit
            )
        }
    }

    private func enqueueLimitEnforcement() {
        let retention = retention
        let imageLimit = imageStorageLimitMB
        enqueuePersistence { historyStore in
            await historyStore.enforce(
                retention: retention,
                imageStorageLimitMB: imageLimit
            )
        }
    }

    private func enqueuePersistence(
        snapshotRevision: UInt64? = nil,
        _ operation: @escaping @Sendable (ClipboardHistoryStore) async -> [ClipboardEntry]?
    ) {
        let expectedRevision = snapshotRevision ?? mutationRevision
        let previous = persistenceTask
        let historyStore = historyStore
        persistenceTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let snapshot = await operation(historyStore)
            guard let self else { return }
            var shouldNotify = false
            if let snapshot {
                hasLoadedHistory = true
                if mutationRevision == expectedRevision {
                    entries = Self.trimmedDisplayOrder(snapshot, memoryWindow: memoryWindow)
                    shouldNotify = true
                }
                if pendingLimitEnforcement {
                    pendingLimitEnforcement = false
                    enqueueLimitEnforcement()
                }
            }
            scheduleStorageUsageRefresh()
            if shouldNotify {
                notifyChanged()
            }
        }
    }

    private func scheduleStorageUsageRefresh() {
        storageUsageRefreshTask?.cancel()
        let historyStore = historyStore
        storageUsageRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let usage = await historyStore.storageUsageBytes()
            guard !Task.isCancelled, let self else { return }
            storageUsageBytes = usage
        }
    }

    private func notifyChanged() {
        onChange?()
        objectWillChange.send()
    }

    @discardableResult
    private func recordLocalMutation() -> UInt64 {
        mutationRevision &+= 1
        return mutationRevision
    }

    private func invalidatePendingCaptures() {
        captureGeneration &+= 1
    }

    private func markInternalWrite(on pasteboard: NSPasteboard) {
        pasteboard.setData(Data([1]), forType: Self.internalPasteboardType)
        lastChangeCount = pasteboard.changeCount
    }

    private func cleanupUnpersistedImage(_ image: ImageClipboardContent) {
        guard image.ownsCachedFiles else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(atPath: image.thumbnailPath)
            if let originalPath = image.originalPath {
                try? FileManager.default.removeItem(atPath: originalPath)
            }
        }
    }

    private static func displayOrder(_ entries: [ClipboardEntry]) -> [ClipboardEntry] {
        let pinned = entries.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
        let regular = entries.filter { !$0.isPinned }.sorted { $0.copiedAt > $1.copiedAt }
        return pinned + regular
    }

    private static func trimmedDisplayOrder(
        _ entries: [ClipboardEntry],
        memoryWindow: Int
    ) -> [ClipboardEntry] {
        let ordered = displayOrder(entries)
        let pinned = ordered.filter(\.isPinned)
        let regular = ordered.filter { !$0.isPinned }.prefix(memoryWindow)
        return pinned + regular
    }
}
