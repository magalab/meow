import AppKit
import CryptoKit
import Foundation

enum SpeechModelState: Equatable, Sendable {
    case notInstalled
    case downloading(Double)
    case installed
    case failed(String)
}

@MainActor
final class SpeechModelStore: ObservableObject {
    @Published private(set) var state: SpeechModelState = .notInstalled
    @Published private(set) var selectedModel: SpeechModelKind = .senseVoice

    let modelsRootDirectory: URL

    private var downloadTask: Task<Void, Never>?
    private var downloadID: UUID?

    init(fileManager: FileManager = .default) {
        let appSupport = Self.appSupportDirectory(fileManager: fileManager)
        modelsRootDirectory = appSupport
            .appendingPathComponent("Meow", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("ASR", isDirectory: true)
        refreshState()
    }

    deinit {
        downloadTask?.cancel()
    }

    var modelDirectory: URL {
        directory(for: selectedModel)
    }

    var isInstalled: Bool {
        isInstalled(for: selectedModel)
    }

    func apply(selectedModel: SpeechModelKind) {
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
        guard downloadTask == nil else { return }
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

    func deleteModel(for model: SpeechModelKind) {
        cancelDownload()
        try? FileManager.default.removeItem(at: directory(for: model))
        if selectedModel == model {
            state = .notInstalled
        }
    }

    func openModelFolder() {
        openModelFolder(for: selectedModel)
    }

    func openModelFolder(for model: SpeechModelKind) {
        let directory = directory(for: model)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private func isInstalled(for model: SpeechModelKind) -> Bool {
        let directory = directory(for: model)
        return model.requiredRelativePaths.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    private func directory(for model: SpeechModelKind) -> URL {
        modelsRootDirectory.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    }

    private nonisolated static func appSupportDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    private func performDownload(for model: SpeechModelKind, downloadID: UUID) async throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("Meow-ASR-\(model.storageDirectoryName)-\(UUID().uuidString)", isDirectory: true)
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

        try Self.validateStagingContents(for: model, in: staging, fileManager: fileManager)

        let targetDirectory = directory(for: model)
        let replacement = modelsRootDirectory.appendingPathComponent(".\(model.storageDirectoryName)-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: replacement, withIntermediateDirectories: true)
        for relativePath in model.requiredRelativePaths {
            let source = staging.appendingPathComponent(relativePath)
            let destination = replacement.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: source, to: destination)
        }

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
                    do {
                        try fileManager.moveItem(at: backupDirectory, to: targetDirectory)
                    } catch {
                        NSLog("[Meow] Failed to restore the previous speech model: \(error.localizedDescription)")
                    }
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
        for model: SpeechModelKind,
        in staging: URL,
        fileManager: FileManager = .default
    ) throws {
        guard model.requiredRelativePaths.allSatisfy({
            fileManager.fileExists(atPath: staging.appendingPathComponent($0).path)
        }) else { throw SpeechModelError.missingDownload }
    }

    private nonisolated func download(
        _ remoteURL: URL,
        to destinationURL: URL,
        expectedSHA256: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = SpeechDownloadDelegate(progress: progress)
        let temporaryURL = try await delegate.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()

        let digest = try Self.sha256(of: temporaryURL)
        guard digest == expectedSHA256 else {
            throw SpeechModelError.checksumMismatch
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

private enum SpeechModelError: LocalizedError {
    case checksumMismatch
    case missingDownload

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return L10n.speechModelChecksumFailed
        case .missingDownload:
            return L10n.speechModelDownloadFailed
        }
    }
}

private final class SpeechDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
            self.cancel()
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
            .appendingPathComponent("Meow-download-\(UUID().uuidString)")
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

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        } else {
            lock.lock()
            let downloadedURL = self.downloadedURL
            lock.unlock()
            if let downloadedURL {
                finish(.success(downloadedURL))
            } else {
                finish(.failure(SpeechModelError.missingDownload))
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
