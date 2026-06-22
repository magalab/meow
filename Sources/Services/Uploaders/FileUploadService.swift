import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

enum FileUploadNotifications {
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifySuccess(filename: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.uploadNotificationTitle
        content.body = filename
        UNUserNotificationCenter.current().add(.init(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }
}

@MainActor
final class FileUploadService: ObservableObject {
    private struct CompletedUpload: Sendable {
        let result: UploadResult
        let fileURL: URL
        let settings: FileHostSettings
    }

    @Published private(set) var isUploading = false
    @Published private(set) var progress: UploadProgress?
    @Published private(set) var lastError: String?

    let historyStore: UploadHistoryStore
    private let settings: () -> FileHostSettings
    private let credentials: any FileUploadCredentialStoring
    private let factory: any UploaderCreating
    private let notifySuccess: (String) -> Void
    private let verifyShareURL: @Sendable (URL) async throws -> Void
    private var activeTask: Task<CompletedUpload, Error>?
    private var runtimeUploader: (any FileUploader)?
    private var runtimeConfig: S3Config?
    private var runtimeSecret: String?

    init(
        historyStore: UploadHistoryStore,
        settings: @escaping () -> FileHostSettings,
        credentials: any FileUploadCredentialStoring = FileUploadCredentialStore(),
        factory: any UploaderCreating = UploaderFactory(),
        notifySuccess: @escaping (String) -> Void = FileUploadNotifications.notifySuccess,
        verifyShareURL: @escaping @Sendable (URL) async throws -> Void = FileUploadService.verifyShareURL
    ) {
        self.historyStore = historyStore
        self.settings = settings
        self.credentials = credentials
        self.factory = factory
        self.notifySuccess = notifySuccess
        self.verifyShareURL = verifyShareURL
    }

    @discardableResult
    func upload(fileURL: URL) async throws -> String {
        let completed = try await executeUpload(fileURL: fileURL)
        return await finish(
            result: completed.result,
            fileURL: completed.fileURL,
            settings: completed.settings
        )
    }

    private func executeUpload(fileURL: URL) async throws -> CompletedUpload {
        guard !isUploading else { throw UploadError.alreadyUploading }
        isUploading = true
        lastError = nil
        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        let current = settings()
        let owner = self
        let task = Task<CompletedUpload, Error> {
            let result = try await owner.performUpload(fileURL: fileURL, settings: current)
            return CompletedUpload(result: result, fileURL: fileURL, settings: current)
        }
        activeTask = task
        defer {
            if hasSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
            isUploading = false
            activeTask = nil
        }
        do {
            return try await task.value
        } catch is CancellationError {
            lastError = UploadError.cancelled.localizedDescription
            throw UploadError.cancelled
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func uploadFromClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = urls.first
        {
            return try await upload(fileURL: fileURL)
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw UploadError.clipboardContentUnavailable }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeowUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("clipboard-\(UUID().uuidString).png")
        try png.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await upload(fileURL: url)
    }

    func testUpload(fileURL: URL) async throws -> String {
        let completed = try await executeUpload(fileURL: fileURL)
        let url = completed.result.shareURL
        try await verifyShareURL(url)
        return await finish(
            result: completed.result,
            fileURL: completed.fileURL,
            settings: completed.settings
        )
    }

    nonisolated private static func verifyShareURL(_ url: URL) async throws {
        let displayURL = sanitizedDisplayURL(url)
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        if let (_, headResponse) = try? await URLSession.shared.data(for: head),
           let response = headResponse as? HTTPURLResponse,
           (200..<400).contains(response.statusCode)
        { return }
        var get = URLRequest(url: url)
        get.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, getResponse) = try await URLSession.shared.bytes(for: get)
        guard let response = getResponse as? HTTPURLResponse else {
            throw UploadError.shareURLInvalidResponse(displayURL)
        }
        guard (200..<400).contains(response.statusCode) else {
            throw UploadError.shareURLVerificationFailed(response.statusCode, displayURL)
        }
        var iterator = bytes.makeAsyncIterator()
        _ = try await iterator.next()
    }

    nonisolated private static func sanitizedDisplayURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? url.absoluteString
    }

    func copyLink(for entry: UploadHistoryEntry) async throws -> String {
        let current = settings()
        guard entry.backendKind == "s3" else { throw UploadError.notConfigured }
        let url: URL
        if let saved = entry.uploadedURL, let permanent = URL(string: saved) {
            url = permanent
        } else {
            guard let config = current.s3Configuration(id: entry.backendConfigID) else {
                throw UploadError.notConfigured
            }
            guard let secret = try credentials.secret(for: config.id), !secret.isEmpty else {
                throw UploadError.secretRequired
            }
            let uploader = try await uploader(config: config, secret: secret)
            url = try await uploader.shareURL(for: entry.objectKey)
        }
        let formatted = current.linkFormat.format(url: url, filename: entry.filename, mimeType: entry.mimeType)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        return formatted
    }

    func removeHistoryEntry(_ entry: UploadHistoryEntry, deleteRemoteObject shouldDeleteRemoteObject: Bool) async throws {
        if shouldDeleteRemoteObject {
            try await deleteRemoteObject(for: entry)
        }
        await historyStore.remove(entry)
    }

    func removeAllHistory(deleteRemoteObjects: Bool) async throws {
        guard deleteRemoteObjects else {
            await historyStore.removeAll()
            return
        }
        await historyStore.waitUntilLoaded()
        var failedFilenames: [String] = []
        for entry in historyStore.entries {
            do {
                try await deleteRemoteObject(for: entry)
                await historyStore.remove(entry)
            } catch {
                failedFilenames.append(entry.filename)
            }
        }
        if !failedFilenames.isEmpty {
            throw UploadError.remoteDeletionFailed(failedFilenames.joined(separator: ", "))
        }
    }

    private func deleteRemoteObject(for entry: UploadHistoryEntry) async throws {
        guard entry.backendKind == "s3",
              let config = settings().s3Configuration(id: entry.backendConfigID)
        else { throw UploadError.notConfigured }
        guard let secret = try credentials.secret(for: config.id), !secret.isEmpty else {
            throw UploadError.secretRequired
        }
        let uploader = try await uploader(config: config, secret: secret)
        try await uploader.deleteObject(for: entry.objectKey)
    }

    func cancel() {
        activeTask?.cancel()
    }

    func shutdown() async {
        activeTask?.cancel()
        _ = try? await activeTask?.value
        if let runtimeUploader { try? await runtimeUploader.shutdown() }
        runtimeUploader = nil
        runtimeConfig = nil
        runtimeSecret = nil
    }

    func saveSecret(_ value: String, for configID: UUID) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UploadError.secretRequired
        }
        try credentials.save(secret: value, for: configID)
    }

    func deleteCredential(for configID: UUID) async throws {
        try credentials.deleteSecret(for: configID)
        await shutdown()
    }

    func loadSecret(for configID: UUID) throws -> String? {
        try credentials.secret(for: configID)
    }

    private func finish(result: UploadResult, fileURL: URL, settings: FileHostSettings) async -> String {
        let formatted = settings.linkFormat.format(
            url: result.shareURL,
            filename: fileURL.lastPathComponent,
            mimeType: result.mimeType
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        let id = UUID()
        let thumbnail = result.mimeType.hasPrefix("image/")
            ? await historyStore.makeThumbnail(for: fileURL, id: id)
            : nil
        await historyStore.add(.init(
            id: id,
            filename: fileURL.lastPathComponent,
            fileSize: result.fileSize,
            mimeType: result.mimeType,
            uploadedURL: settings.s3.publicURLStrategy == .presigned ? nil : result.shareURL.absoluteString,
            objectKey: result.objectKey,
            backendKind: "s3",
            backendConfigID: settings.s3.id,
            backendName: settings.s3.name,
            thumbnailPath: thumbnail,
            createdAt: Date()
        ), limit: settings.historyLimit)
        notifySuccess(fileURL.lastPathComponent)
        return formatted
    }

    private func validate(config: S3Config) throws {
        guard config.isEnabled,
              !config.accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !config.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw UploadError.notConfigured }
        if config.publicURLStrategy == .customDomain,
           config.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw UploadError.shareURLNotConfigured
        }
        let endpointHost = URLComponents(string: config.endpoint)?.host?.lowercased() ?? ""
        let isR2 = config.region.lowercased() == "auto" || endpointHost.hasSuffix(".r2.cloudflarestorage.com")
        if isR2 {
            let endpoint = URLComponents(string: config.endpoint)
            let host = endpoint?.host?.lowercased() ?? ""
            let path = endpoint?.path ?? ""
            guard host.hasSuffix(".r2.cloudflarestorage.com"),
                  host != "r2.cloudflarestorage.com",
                  path.isEmpty || path == "/",
                  endpoint?.query == nil,
                  endpoint?.fragment == nil
            else { throw UploadError.invalidR2Endpoint }
        }
        if config.publicURLStrategy == .publicBucket,
           isR2,
           config.publicBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw UploadError.shareURLNotConfigured
        }
    }

    private func uploader(config: S3Config, secret: String) async throws -> any FileUploader {
        if let runtimeUploader, runtimeConfig == config, runtimeSecret == secret {
            return runtimeUploader
        }
        if let runtimeUploader { try? await runtimeUploader.shutdown() }
        let created = try factory.makeUploader(config: config, secretAccessKey: secret)
        runtimeUploader = created
        runtimeConfig = config
        runtimeSecret = secret
        return created
    }

    private func performUpload(fileURL: URL, settings: FileHostSettings) async throws -> UploadResult {
        let config = settings.s3
        try validate(config: config)
        let credentials = self.credentials
        guard let secret = try await Task.detached(priority: .userInitiated, operation: {
            try credentials.secret(for: config.id)
        }).value, !secret.isEmpty else {
            throw UploadError.secretRequired
        }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try Self.prepareUpload(fileURL: fileURL, settings: settings)
        }.value
        try Task.checkCancellation()
        let uploader = try await uploader(config: config, secret: secret)
        let request = UploadRequest(
            fileURL: fileURL,
            objectKey: prepared.objectKey,
            fileSize: prepared.fileSize,
            mimeType: prepared.mimeType
        )
        progress = .init(sentBytes: 0, totalBytes: prepared.fileSize)
        let owner = self
        return try await uploader.upload(request) { value in
            Task { @MainActor in owner.progress = value }
        }
    }

    nonisolated private static func prepareUpload(
        fileURL: URL,
        settings: FileHostSettings
    ) throws -> (fileSize: Int64, mimeType: String, objectKey: String) {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw UploadError.fileUnreadable(fileURL.lastPathComponent)
        }
        let fileSize = Int64(values.fileSize ?? 0)
        let maximumMB = min(max(1, settings.maximumFileSizeMB), Int(Int64.max / 1_024 / 1_024))
        let limit = Int64(maximumMB) * 1_024 * 1_024
        guard fileSize <= limit else { throw UploadError.fileTooLarge(limit) }
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let objectKey = try ObjectKeyBuilder.build(
            template: settings.s3.objectKeyTemplate,
            fileURL: fileURL
        )
        return (fileSize, mimeType, objectKey)
    }
}
