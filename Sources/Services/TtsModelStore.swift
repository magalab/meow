import AppKit
import CryptoKit
import Foundation

enum TtsModelState: Equatable, Sendable {
    case notInstalled
    case downloading(Double)
    case installed
    case failed(String)
}

@MainActor
final class TtsModelStore: ObservableObject {
    @Published private(set) var state: TtsModelState = .installed
    @Published private(set) var selectedModel: TtsModelKind = .system

    let modelsRootDirectory: URL

    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?

    init(fileManager: FileManager = .default, modelsRootDirectory: URL? = nil) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        self.modelsRootDirectory = modelsRootDirectory ?? appSupport
            .appendingPathComponent("Meow", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("TTS", isDirectory: true)
        refreshState()
    }

    deinit {
        downloadTask?.cancel()
    }

    var modelDirectory: URL {
        modelsRootDirectory.appendingPathComponent(selectedModel.storageDirectoryName, isDirectory: true)
    }

    var isInstalled: Bool {
        isInstalled(for: selectedModel)
    }

    func apply(selectedModel: TtsModelKind) {
        if self.selectedModel != selectedModel {
            cancelDownload()
        }
        self.selectedModel = selectedModel
        refreshState()
    }

    func refreshState() {
        guard !isDownloading else { return }
        state = isInstalled ? .installed : .notInstalled
    }

    func downloadModel() {
        guard selectedModel != .system, downloadTask == nil else { return }
        let model = selectedModel
        let downloadID = UUID()
        self.downloadID = downloadID
        state = .downloading(0)

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performDownload(for: model, downloadID: downloadID)
                guard !Task.isCancelled, self.downloadID == downloadID else { return }
                self.state = .installed
            } catch where Task.isCancelled {
                if self.downloadID == downloadID {
                    self.refreshState()
                }
            } catch {
                if self.downloadID == downloadID {
                    self.state = .failed(error.localizedDescription)
                }
            }
            if self.downloadID == downloadID {
                self.downloadTask = nil
                self.downloadID = nil
            }
        }
    }

    func cancelDownload() {
        let task = downloadTask
        downloadTask = nil
        downloadID = nil
        task?.cancel()
        state = isInstalled ? .installed : .notInstalled
    }

    func deleteModel() {
        deleteModel(for: selectedModel)
    }

    func deleteModel(for model: TtsModelKind) {
        cancelDownload()
        try? FileManager.default.removeItem(at: directory(for: model))
        if selectedModel == model {
            state = .notInstalled
        }
    }

    func openModelFolder() {
        let directory = directory(for: selectedModel)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func configurationDirectory(for model: TtsModelKind) -> URL? {
        modelsRootDirectory.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private func isInstalled(for model: TtsModelKind) -> Bool {
        model.requiredRelativePaths.allSatisfy {
            FileManager.default.fileExists(atPath: directory(for: model).appendingPathComponent($0).path)
        }
    }

    private func directory(for model: TtsModelKind) -> URL {
        modelsRootDirectory.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    }

    private func performDownload(for model: TtsModelKind, downloadID: UUID) async throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("Meow-TTS-\(model.storageDirectoryName)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for (index, artifact) in model.manifest.artifacts.enumerated() {
            let destination = staging.appendingPathComponent(artifact.relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await download(
                artifact.remoteURL,
                to: destination,
                expectedSHA256: artifact.sha256
            ) { [weak self] progress in
                Task { @MainActor in
                    guard self?.downloadID == downloadID else { return }
                    let base = Double(index) / Double(max(model.manifest.artifacts.count, 1))
                    let span = progress / Double(max(model.manifest.artifacts.count, 1))
                    self?.state = .downloading(base + span)
                }
            }
            try Task.checkCancellation()
        }

        try Self.validateStagingContents(for: model, in: staging)

        let targetDirectory = directory(for: model)
        let replacement = modelsRootDirectory.appendingPathComponent(
            ".\(model.storageDirectoryName)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.moveItem(at: staging, to: replacement)

        try fileManager.createDirectory(at: modelsRootDirectory, withIntermediateDirectories: true)
        var backupDirectory: URL?
        var replacementInstalled = false
        defer {
            if !replacementInstalled, fileManager.fileExists(atPath: replacement.path) {
                try? fileManager.removeItem(at: replacement)
            }
            if let backupDirectory,
               fileManager.fileExists(atPath: backupDirectory.path)
            {
                if fileManager.fileExists(atPath: targetDirectory.path) {
                    try? fileManager.removeItem(at: backupDirectory)
                } else {
                    try? fileManager.moveItem(at: backupDirectory, to: targetDirectory)
                }
            }
        }

        if fileManager.fileExists(atPath: targetDirectory.path) {
            let backup = modelsRootDirectory.appendingPathComponent(
                ".\(model.storageDirectoryName)-backup-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: targetDirectory, to: backup)
            backupDirectory = backup
        }
        try fileManager.moveItem(at: replacement, to: targetDirectory)
        replacementInstalled = true
        if let backupDirectory {
            try? fileManager.removeItem(at: backupDirectory)
        }
    }

    nonisolated static func validateStagingContents(
        for model: TtsModelKind,
        in staging: URL,
        fileManager: FileManager = .default
    ) throws {
        guard model.requiredRelativePaths.allSatisfy({
            fileManager.fileExists(atPath: staging.appendingPathComponent($0).path)
        }) else {
            throw TtsModelError.missingDownload
        }
    }

    private nonisolated func download(
        _ remoteURL: URL,
        to destinationURL: URL,
        expectedSHA256: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = TtsDownloadDelegate(progress: progress)
        let temporaryURL = try await delegate.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()

        let digest = try Self.sha256(of: temporaryURL)
        guard digest == expectedSHA256 else {
            throw TtsModelError.checksumMismatch
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private enum TtsModelError: LocalizedError {
    case checksumMismatch
    case missingDownload

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return L10n.ttsErrorModelChecksum
        case .missingDownload:
            return L10n.ttsErrorIncompleteModel
        }
    }
}

private final class TtsDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var downloadedURL: URL?
    private var isFinished = false

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func download(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                lock.lock()
                let isFinished = self.isFinished
                if !isFinished {
                    self.continuation = continuation
                    self.session = session
                }
                lock.unlock()

                guard !isFinished else {
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            cancel()
        }
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let retainedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Meow-TTS-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: retainedURL)
            lock.lock()
            let shouldKeep = !isFinished
            if shouldKeep {
                downloadedURL = retainedURL
            }
            lock.unlock()
            if !shouldKeep {
                try? FileManager.default.removeItem(at: retainedURL)
            }
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            lock.lock()
            let downloadedURL = self.downloadedURL
            lock.unlock()
            if let downloadedURL {
                finish(.success(downloadedURL))
            } else {
                finish(.failure(TtsModelError.missingDownload))
            }
        }
    }

    private func cancel() {
        let session: URLSession?
        let continuation: CheckedContinuation<URL, Error>?
        let downloadedURL: URL?

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        session = self.session
        continuation = self.continuation
        downloadedURL = self.downloadedURL
        self.session = nil
        self.continuation = nil
        self.downloadedURL = nil
        lock.unlock()

        session?.invalidateAndCancel()
        if let downloadedURL {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<URL, Error>) {
        let session: URLSession?
        let continuation: CheckedContinuation<URL, Error>?
        let downloadedURL: URL?

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            if case let .success(url) = result {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        isFinished = true
        session = self.session
        continuation = self.continuation
        downloadedURL = self.downloadedURL
        self.downloadedURL = nil
        self.continuation = nil
        self.session = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        if case .failure = result, let downloadedURL {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
        continuation?.resume(with: result)
    }
}
