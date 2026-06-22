import AppKit
import Foundation
import Testing
@testable import Meow

@Test("SwiftPM executable mode disables UserNotifications safely")
func swiftPMNotificationFallback() {
    #expect(!FileUploadNotifications.isAvailable)
    FileUploadNotifications.requestAuthorization()
    FileUploadNotifications.notifySuccess(filename: "test.txt")
}

private final class MemorySecurityClient: FileUploadSecurityClient, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.withLock { values["\(service):\(account)"] }
    }
    func save(_ data: Data, service: String, account: String) throws {
        lock.withLock { values["\(service):\(account)"] = data }
    }
    func delete(service: String, account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: "\(service):\(account)") }
    }
}

@Test("Credential store creates updates reads and deletes secrets")
func credentialStoreCRUD() throws {
    let client = MemorySecurityClient()
    let store = FileUploadCredentialStore(bundleIdentifier: "test.meow", client: client)
    let id = UUID()
    #expect(try store.secret(for: id) == nil)
    try store.save(secret: "first", for: id)
    #expect(try store.secret(for: id) == "first")
    try store.save(secret: "second", for: id)
    #expect(try store.secret(for: id) == "second")
    try store.deleteSecret(for: id)
    #expect(try store.secret(for: id) == nil)
}

@Test("Older settings default file hosting to disabled")
func fileHostingSettingsCompatibility() throws {
    let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(settings.fileHosting == .default)
    #expect(!settings.fileHosting.s3.isEnabled)
    #expect(settings.fileHosting.maximumFileSizeMB == 5120)
}

@Test("Partial S3 configuration decodes with field defaults")
func partialS3SettingsCompatibility() throws {
    let config = try JSONDecoder().decode(S3Config.self, from: Data(#"{"bucket":"archive"}"#.utf8))
    #expect(config.bucket == "archive")
    #expect(config.region == "us-east-1")
    #expect(config.objectKeyTemplate.contains("{random}"))
    #expect(!config.isEnabled)
}

@Test("Legacy single S3 configuration migrates into the saved configuration list")
func legacyS3ConfigurationMigration() throws {
    let id = UUID()
    let data = Data(#"{"s3":{"id":"\#(id.uuidString)","bucket":"archive","isEnabled":true}}"#.utf8)
    let settings = try JSONDecoder().decode(FileHostSettings.self, from: data)

    #expect(settings.s3Configurations.count == 1)
    #expect(settings.selectedS3ConfigID == id)
    #expect(settings.s3.id == id)
    #expect(settings.s3.bucket == "archive")
    #expect(settings.s3.name == "S3")
}

@Test("Saved S3 configurations preserve names and selection")
func multipleS3ConfigurationsRoundTrip() throws {
    var settings = FileHostSettings()
    settings.s3.name = "Work R2"
    var personal = S3Config()
    personal.name = "Personal MinIO"
    personal.bucket = "photos"
    settings.s3Configurations.append(personal)
    settings.selectedS3ConfigID = personal.id

    let decoded = try JSONDecoder().decode(
        FileHostSettings.self,
        from: JSONEncoder().encode(settings)
    )

    #expect(decoded.s3Configurations.map(\.name) == ["Work R2", "Personal MinIO"])
    #expect(decoded.selectedS3ConfigID == personal.id)
    #expect(decoded.s3.bucket == "photos")
    #expect(decoded.s3Configuration(id: settings.s3Configurations[0].id)?.name == "Work R2")
}

@Test("Object key expansion removes unsafe path segments")
func objectKeyExpansionAndSanitization() throws {
    let date = Date(timeIntervalSince1970: 1_765_843_200)
    let file = URL(fileURLWithPath: "/tmp/报告 #1.png")
    let key = try ObjectKeyBuilder.build(
        template: "/{year}//../{month}/{filename}-{random}.{ext}",
        fileURL: file,
        date: date,
        random: "abcdef12"
    )
    #expect(!key.hasPrefix("/"))
    #expect(!key.contains(".."))
    #expect(key.hasSuffix("报告 #1-abcdef12.png"))
    #expect(ObjectKeyBuilder.encodedPath(key).contains("%23"))
    #expect(ObjectKeyBuilder.encodedPath("a&b.txt") == "a%26b.txt")
    #expect(ObjectKeyBuilder.encodedPath(key).contains("%E6%8A%A5%E5%91%8A"))
}

@Test("Object key rejects an empty expanded path")
func objectKeyRejectsEmptyPath() {
    #expect(throws: UploadError.invalidObjectKey) {
        try ObjectKeyBuilder.build(template: "/../", fileURL: URL(fileURLWithPath: "/tmp/a.txt"))
    }
}

@Test("Link formats escape file names and HTML attributes")
func linkFormatting() throws {
    let url = try #require(URL(string: "https://cdn.example/a%20b.png?x=1&y=2"))
    #expect(LinkFormat.markdown.format(url: url, filename: "a[b].txt", mimeType: "text/plain") == "[a\\[b\\].txt](https://cdn.example/a%20b.png?x=1&y=2)")
    let html = LinkFormat.html.format(url: url, filename: "a\"&.txt", mimeType: "text/plain")
    #expect(html.contains("&quot;"))
    #expect(html.contains("&amp;"))
}

@Test("Upload history enforces retention and tolerates corrupt index")
@MainActor
func uploadHistoryRetentionAndCorruption() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = UploadHistoryStore(directoryURL: root)
    for index in 0..<4 {
        await store.add(.init(
            id: UUID(), filename: "\(index).txt", fileSize: 1, mimeType: "text/plain",
            uploadedURL: "https://example.com/\(index)", objectKey: "\(index)", backendKind: "s3",
            backendConfigID: UUID(), thumbnailPath: nil, createdAt: Date()
        ), limit: 2)
    }
    #expect(store.entries.map(\.filename) == ["3.txt", "2.txt"])
    try Data("not-json".utf8).write(to: root.appendingPathComponent("index.json"))
    let corrupted = UploadHistoryStore(directoryURL: root)
    await corrupted.waitUntilLoaded()
    #expect(corrupted.entries.isEmpty)
}

@Test("Missing history thumbnails degrade to the file icon path")
@MainActor
func missingHistoryThumbnail() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = UploadHistoryStore(directoryURL: root)
    await store.waitUntilLoaded()
    let entry = UploadHistoryEntry(
        id: UUID(), filename: "image.png", fileSize: 1, mimeType: "image/png",
        uploadedURL: "https://example.com/image.png", objectKey: "image.png", backendKind: "s3",
        backendConfigID: UUID(), thumbnailPath: "missing.jpg", createdAt: Date()
    )
    let url = store.thumbnailURL(for: entry)
    #expect(url != nil)
    #expect(url.flatMap(NSImage.init(contentsOf:)) == nil)
}

@Test("Status-item drop layer does not intercept button clicks")
@MainActor
func statusItemDropLayerClickThrough() {
    let view = StatusItemDropView(isEnabled: true, onDrop: { _ in })
    view.frame = NSRect(x: 0, y: 0, width: 40, height: 24)
    #expect(view.hitTest(NSPoint(x: 20, y: 12)) == nil)
    #expect(!view.isAccessibilityElement())
    #expect(view.registeredDraggedTypes.contains(.fileURL))
}

private struct TestCredentialStore: FileUploadCredentialStoring {
    let value: String?
    func secret(for _: UUID) throws -> String? { value }
    func save(secret _: String, for _: UUID) throws {}
    func deleteSecret(for _: UUID) throws {}
}

@Test("Upload secrets require a value and are saved for the explicit configuration")
@MainActor
func uploadSecretValidationAndConfigurationBinding() throws {
    let client = MemorySecurityClient()
    let credentials = FileUploadCredentialStore(bundleIdentifier: "test.meow", client: client)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root),
        settings: { .default },
        credentials: credentials,
        factory: TestUploaderFactory(uploader: TestUploader(url: URL(string: "https://example.com")!)),
        notifySuccess: { _ in }
    )
    let selectedID = UUID()
    let otherID = UUID()

    #expect(throws: UploadError.secretRequired) {
        try service.saveSecret("   ", for: selectedID)
    }
    try service.saveSecret("secret", for: selectedID)
    #expect(try credentials.secret(for: selectedID) == "secret")
    #expect(try credentials.secret(for: otherID) == nil)
}

private struct TestUploaderFactory: UploaderCreating {
    let uploader: any FileUploader
    func makeUploader(config _: S3Config, secretAccessKey _: String) throws -> any FileUploader { uploader }
}

private struct TestUploader: FileUploader {
    let url: URL
    func upload(_ request: UploadRequest, progress: @escaping @Sendable (UploadProgress) -> Void) async throws -> UploadResult {
        progress(.init(sentBytes: request.fileSize, totalBytes: request.fileSize))
        return .init(objectKey: request.objectKey, shareURL: url, fileSize: request.fileSize, mimeType: request.mimeType)
    }
    func shareURL(for _: String) async throws -> URL { url }
}

private struct SlowUploader: FileUploader {
    let url: URL
    func upload(_ request: UploadRequest, progress _: @escaping @Sendable (UploadProgress) -> Void) async throws -> UploadResult {
        try await Task.sleep(for: .milliseconds(200))
        return .init(objectKey: request.objectKey, shareURL: url, fileSize: request.fileSize, mimeType: request.mimeType)
    }
    func shareURL(for _: String) async throws -> URL { url }
}

private struct FailingUploader: FileUploader {
    func upload(_: UploadRequest, progress _: @escaping @Sendable (UploadProgress) -> Void) async throws -> UploadResult {
        throw UploadError.networkError("offline")
    }
    func shareURL(for _: String) async throws -> URL { throw UploadError.networkError("offline") }
}

private final class RemoteDeletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []
    func record(_ key: String) { lock.withLock { keys.append(key) } }
    var deletedKeys: [String] { lock.withLock { keys } }
}

private struct DeletingUploader: FileUploader {
    let state: RemoteDeletionState
    let error: UploadError?

    func upload(_: UploadRequest, progress _: @escaping @Sendable (UploadProgress) -> Void) async throws -> UploadResult {
        throw UploadError.notConfigured
    }

    func shareURL(for _: String) async throws -> URL {
        throw UploadError.notConfigured
    }

    func deleteObject(for objectKey: String) async throws {
        if let error { throw error }
        state.record(objectKey)
    }
}

private final class RuntimeTrackingState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var creations = 0
    private(set) var shutdowns = 0
    func created() { lock.withLock { creations += 1 } }
    func shutDown() { lock.withLock { shutdowns += 1 } }
}

private struct RuntimeTrackingFactory: UploaderCreating {
    let state: RuntimeTrackingState
    let url: URL
    func makeUploader(config _: S3Config, secretAccessKey _: String) throws -> any FileUploader {
        state.created()
        return RuntimeTrackingUploader(state: state, url: url)
    }
}

private struct RuntimeTrackingUploader: FileUploader {
    let state: RuntimeTrackingState
    let url: URL
    func upload(_ request: UploadRequest, progress _: @escaping @Sendable (UploadProgress) -> Void) async throws -> UploadResult {
        .init(objectKey: request.objectKey, shareURL: url, fileSize: request.fileSize, mimeType: request.mimeType)
    }
    func shareURL(for _: String) async throws -> URL { url }
    func shutdown() async throws { state.shutDown() }
}

private func configuredSettings(strategy: S3PublicURLStrategy = .publicBucket) -> FileHostSettings {
    var settings = FileHostSettings.default
    settings.s3.isEnabled = true
    settings.s3.accessKeyID = "key"
    settings.s3.bucket = "bucket"
    settings.s3.publicURLStrategy = strategy
    settings.s3.publicBaseURL = strategy == .customDomain ? "https://cdn.example" : ""
    settings.linkFormat = .url
    return settings
}

@Test("Upload service writes history and returns a formatted link")
@MainActor
func uploadServiceSuccess() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("hello world.txt")
    try Data("hello".utf8).write(to: file)
    var settings = FileHostSettings.default
    settings.s3.isEnabled = true
    settings.s3.name = "R2"
    settings.s3.accessKeyID = "key"
    settings.s3.bucket = "bucket"
    settings.s3.publicURLStrategy = .publicBucket
    settings.linkFormat = .markdown
    let expectedURL = try #require(URL(string: "https://cdn.example/hello%20world.txt"))
    let history = UploadHistoryStore(directoryURL: root.appendingPathComponent("history"))
    let service = FileUploadService(
        historyStore: history,
        settings: { settings },
        credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: TestUploader(url: expectedURL)),
        notifySuccess: { _ in }
    )

    let result = try await service.upload(fileURL: file)
    #expect(result == "[hello world.txt](https://cdn.example/hello%20world.txt)")
    #expect(history.entries.count == 1)
    #expect(history.entries.first?.uploadedURL == expectedURL.absoluteString)
    #expect(history.entries.first?.backendName == "R2")
}

@Test("Legacy upload history without a source name still decodes")
func legacyUploadHistorySourceCompatibility() throws {
    let entry = UploadHistoryEntry(
        id: UUID(), filename: "legacy.txt", fileSize: 1, mimeType: "text/plain",
        uploadedURL: nil, objectKey: "legacy.txt", backendKind: "s3", backendConfigID: UUID(),
        backendName: "R2", thumbnailPath: nil, createdAt: Date()
    )
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    json.removeValue(forKey: "backendName")

    let decoded = try JSONDecoder().decode(
        UploadHistoryEntry.self,
        from: JSONSerialization.data(withJSONObject: json)
    )

    #expect(decoded.backendName == nil)
    #expect(decoded.filename == "legacy.txt")
}

@Test("Upload service permits only one active upload")
@MainActor
func uploadServiceSingleTaskLimit() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    try Data("hello".utf8).write(to: file)
    let settings = configuredSettings()
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root.appendingPathComponent("history")),
        settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: SlowUploader(url: URL(string: "https://example.com/a")!)),
        notifySuccess: { _ in }
    )
    let first = Task { try await service.upload(fileURL: file) }
    await Task.yield()
    await #expect(throws: UploadError.alreadyUploading) { try await service.upload(fileURL: file) }
    _ = try await first.value
}

@Test("Upload cancellation covers the active lifecycle")
@MainActor
func uploadServiceCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    try Data("hello".utf8).write(to: file)
    let settings = configuredSettings()
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root.appendingPathComponent("history")),
        settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: SlowUploader(url: URL(string: "https://example.com/a")!)),
        notifySuccess: { _ in }
    )
    let task = Task { try await service.upload(fileURL: file) }
    try await Task.sleep(for: .milliseconds(20))
    service.cancel()
    await #expect(throws: UploadError.cancelled) { try await task.value }
    #expect(!service.isUploading)
}

@Test("Uploader runtime is reused and rebuilt when configuration changes")
@MainActor
func uploaderRuntimeLifecycle() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    try Data("hello".utf8).write(to: file)
    var settings = configuredSettings()
    let state = RuntimeTrackingState()
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root.appendingPathComponent("history")),
        settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: RuntimeTrackingFactory(state: state, url: URL(string: "https://example.com/a")!),
        notifySuccess: { _ in }
    )
    _ = try await service.upload(fileURL: file)
    _ = try await service.upload(fileURL: file)
    #expect(state.creations == 1)
    #expect(state.shutdowns == 0)
    settings.s3.region = "eu-west-1"
    _ = try await service.upload(fileURL: file)
    #expect(state.creations == 2)
    #expect(state.shutdowns == 1)
    await service.shutdown()
    #expect(state.shutdowns == 2)
}

@Test("R2 public-bucket links require an r2.dev or custom-domain base URL")
@MainActor
func r2PublicURLValidation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    try Data("hello".utf8).write(to: file)
    var settings = configuredSettings()
    settings.s3.region = "auto"
    settings.s3.endpoint = "https://account.r2.cloudflarestorage.com"
    settings.s3.publicURLStrategy = .publicBucket
    settings.s3.publicBaseURL = ""
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root.appendingPathComponent("history")),
        settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: TestUploader(url: URL(string: "https://example.com/a")!)),
        notifySuccess: { _ in }
    )
    await #expect(throws: UploadError.shareURLNotConfigured) {
        try await service.upload(fileURL: file)
    }
}

@Test("R2 requires an account S3 endpoint without a bucket path")
@MainActor
func r2EndpointValidation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    try Data("hello".utf8).write(to: file)
    var settings = configuredSettings(strategy: .customDomain)
    settings.s3.region = "auto"
    settings.s3.endpoint = "https://account.r2.cloudflarestorage.com/bucket"
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root.appendingPathComponent("history")),
        settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: TestUploader(url: URL(string: "https://cdn.example/file")!)),
        notifySuccess: { _ in }
    )

    await #expect(throws: UploadError.invalidR2Endpoint) {
        try await service.upload(fileURL: file)
    }
}

@Test("R2 disables AWS chunked payload signing")
func r2DisablesChunkedPayloadSigning() {
    var config = S3Config()
    config.region = "auto"
    config.endpoint = "https://account.r2.cloudflarestorage.com"
    let options = S3Uploader.serviceOptions(for: config)

    #expect(options.contains(.s3DisableChunkedUploads))
}

@Test("AWS keeps chunked payload signing enabled")
func awsKeepsChunkedPayloadSigning() {
    var config = S3Config()
    config.region = "us-east-1"
    config.endpoint = ""
    let options = S3Uploader.serviceOptions(for: config)

    #expect(!options.contains(.s3DisableChunkedUploads))
    #expect(options.contains(.s3ForceVirtualHost))
}

@Test("S3 error fallback preserves useful localized descriptions")
func s3ErrorFallbackDescription() {
    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
    #expect(S3Uploader.errorMessage(for: error) == error.localizedDescription)
}

@Test("Test upload publishes results only after the share URL is reachable")
@MainActor
func testUploadVerificationFailureHasNoSuccessSideEffects() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file.txt")
    try Data("hello".utf8).write(to: file)
    let settings = configuredSettings()
    let history = UploadHistoryStore(directoryURL: root.appendingPathComponent("history"))
    var notified = false
    let service = FileUploadService(
        historyStore: history, settings: { settings },
        credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: TestUploader(url: URL(string: "https://example.invalid/file")!)),
        notifySuccess: { _ in notified = true },
        verifyShareURL: { _ in throw UploadError.invalidResponse }
    )
    await #expect(throws: UploadError.invalidResponse) {
        try await service.testUpload(fileURL: file)
    }
    await history.waitUntilLoaded()
    #expect(history.entries.isEmpty)
    #expect(!notified)
}

@Test("Remote deletion succeeds before removing upload history")
@MainActor
func remoteDeletionRemovesHistoryAfterObject() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let settings = configuredSettings()
    let history = UploadHistoryStore(directoryURL: root)
    let entry = UploadHistoryEntry(
        id: UUID(), filename: "image.jpeg", fileSize: 10, mimeType: "image/jpeg",
        uploadedURL: "https://example.com/image.jpeg", objectKey: "uploads/image.jpeg", backendKind: "s3",
        backendConfigID: settings.s3.id, thumbnailPath: nil, createdAt: Date()
    )
    await history.add(entry, limit: 10)
    let state = RemoteDeletionState()
    let service = FileUploadService(
        historyStore: history, settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: DeletingUploader(state: state, error: nil)), notifySuccess: { _ in }
    )

    try await service.removeHistoryEntry(entry, deleteRemoteObject: true)

    #expect(state.deletedKeys == ["uploads/image.jpeg"])
    #expect(history.entries.isEmpty)
}

@Test("Remote deletion failure preserves upload history")
@MainActor
func remoteDeletionFailurePreservesHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let settings = configuredSettings()
    let history = UploadHistoryStore(directoryURL: root)
    let entry = UploadHistoryEntry(
        id: UUID(), filename: "image.jpeg", fileSize: 10, mimeType: "image/jpeg",
        uploadedURL: nil, objectKey: "uploads/image.jpeg", backendKind: "s3",
        backendConfigID: settings.s3.id, thumbnailPath: nil, createdAt: Date()
    )
    await history.add(entry, limit: 10)
    let service = FileUploadService(
        historyStore: history, settings: { settings }, credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: DeletingUploader(
            state: RemoteDeletionState(), error: .s3Error("Access denied")
        )), notifySuccess: { _ in }
    )

    await #expect(throws: UploadError.s3Error("Access denied")) {
        try await service.removeHistoryEntry(entry, deleteRemoteObject: true)
    }
    #expect(history.entries == [entry])
}

@Test("Upload errors distinguish invalid storage responses from local input failures")
func uploadErrorDescriptionsAreSpecific() {
    #expect(UploadError.clipboardContentUnavailable.localizedDescription != UploadError.invalidResponse.localizedDescription)
    #expect(UploadError.fileUnreadable("test.txt") != UploadError.invalidResponse)
    #expect(UploadError.shareURLInvalidResponse("https://cdn.example/test.txt") != UploadError.invalidResponse)
}

@Test("Upload file stream keeps returning nil after reaching EOF")
func uploadFileStreamEOFIsStable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("小狗.jpeg")
    try Data("image-data".utf8).write(to: file)
    let iterator = FileChunkSequence(
        url: file,
        chunkSize: 4,
        total: 10,
        progress: { _ in }
    ).makeAsyncIterator()

    #expect(try await iterator.next() == Data("imag".utf8))
    #expect(try await iterator.next() == Data("e-da".utf8))
    #expect(try await iterator.next() == Data("ta".utf8))
    #expect(try await iterator.next() == nil)
    #expect(try await iterator.next() == nil)
}

@Test("S3 share URLs encode each object-key segment")
func s3ShareURLSegmentEncoding() async throws {
    var config = S3Config()
    config.accessKeyID = "key"
    config.bucket = "bucket"
    config.publicURLStrategy = .customDomain
    config.publicBaseURL = "https://cdn.example/base"
    let uploader = try S3Uploader(config: config, secretAccessKey: "secret")
    let url = try await uploader.shareURL(for: "目录/a #&\".txt")
    #expect(url.absoluteString == "https://cdn.example/base/%E7%9B%AE%E5%BD%95/a%20%23%26%22.txt")
    try await uploader.shutdown()
}

@Test("S3 configuration rejects non-HTTP endpoints")
func s3RejectsInvalidEndpoint() {
    var config = S3Config()
    config.accessKeyID = "key"
    config.bucket = "bucket"
    config.endpoint = "file:///tmp/storage"
    #expect(throws: UploadError.publicURLUnavailable) {
        try S3Uploader(config: config, secretAccessKey: "secret")
    }
}

@Test("S3 endpoint host names default to HTTPS")
func s3EndpointWithoutSchemeDefaultsToHTTPS() async throws {
    var config = S3Config()
    config.accessKeyID = "key"
    config.bucket = "archive"
    config.region = "cn-south-1"
    config.endpoint = "s3.cn-south-1.example.com"
    config.publicURLStrategy = .publicBucket
    config.urlStyle = .path
    let uploader = try S3Uploader(config: config, secretAccessKey: "secret")

    let url = try await uploader.shareURL(for: "test.txt")

    #expect(url.absoluteString == "https://s3.cn-south-1.example.com/archive/test.txt")
    try await uploader.shutdown()
}

@Test("S3 dotted buckets use path-style share URLs to preserve TLS validity")
func s3DottedBucketShareURL() async throws {
    var config = S3Config()
    config.accessKeyID = "key"
    config.bucket = "assets.example.com"
    config.region = "ap-southeast-1"
    config.publicURLStrategy = .publicBucket
    config.urlStyle = .virtualHosted
    let uploader = try S3Uploader(config: config, secretAccessKey: "secret")
    let url = try await uploader.shareURL(for: "image.png")
    #expect(url.absoluteString == "https://s3.ap-southeast-1.amazonaws.com/assets.example.com/image.png")
    try await uploader.shutdown()
}

@Test("Clipboard image temporary file is removed after upload failure")
@MainActor
func clipboardTemporaryFileCleanup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let settings = configuredSettings()
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root), settings: { settings },
        credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: FailingUploader()), notifySuccess: { _ in }
    )
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.addRepresentation(bitmap)
    pasteboard.writeObjects([image])
    let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MeowUploads")
    let before = (try? FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)) ?? []
    await #expect(throws: UploadError.networkError("offline")) { try await service.uploadFromClipboard() }
    let after = (try? FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)) ?? []
    #expect(after == before)
}

@Test("History refreshes presigned links and rejects deleted configurations")
@MainActor
func historyPresignedRefresh() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var settings = configuredSettings(strategy: .presigned)
    let historicalConfigID = settings.s3.id
    var currentConfig = S3Config()
    currentConfig.name = "Current"
    settings.s3Configurations.append(currentConfig)
    settings.selectedS3ConfigID = currentConfig.id
    let refreshed = URL(string: "https://example.com/object?signature=new")!
    let service = FileUploadService(
        historyStore: UploadHistoryStore(directoryURL: root), settings: { settings },
        credentials: TestCredentialStore(value: "secret"),
        factory: TestUploaderFactory(uploader: TestUploader(url: refreshed)), notifySuccess: { _ in }
    )
    let entry = UploadHistoryEntry(
        id: UUID(), filename: "file.txt", fileSize: 1, mimeType: "text/plain", uploadedURL: nil,
        objectKey: "file.txt", backendKind: "s3", backendConfigID: historicalConfigID,
        thumbnailPath: nil, createdAt: Date()
    )
    #expect(try await service.copyLink(for: entry) == refreshed.absoluteString)
    let deleted = UploadHistoryEntry(
        id: UUID(), filename: "file.txt", fileSize: 1, mimeType: "text/plain", uploadedURL: nil,
        objectKey: "file.txt", backendKind: "s3", backendConfigID: UUID(),
        thumbnailPath: nil, createdAt: Date()
    )
    await #expect(throws: UploadError.notConfigured) { try await service.copyLink(for: deleted) }
    let permanent = UploadHistoryEntry(
        id: UUID(), filename: "file.txt", fileSize: 1, mimeType: "text/plain",
        uploadedURL: "https://cdn.example/file.txt", objectKey: "file.txt",
        backendKind: "s3", backendConfigID: UUID(), thumbnailPath: nil, createdAt: Date()
    )
    #expect(try await service.copyLink(for: permanent) == "https://cdn.example/file.txt")
}
