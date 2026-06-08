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

    var modelURL: URL {
        modelDirectory.appendingPathComponent(selectedModel.modelFileName)
    }

    var tokensURL: URL {
        modelDirectory.appendingPathComponent(selectedModel.tokensFileName)
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
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(model.modelFileName).path) &&
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(model.tokensFileName).path)
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

        switch model.downloadSource {
        case let .files(files):
            try await downloadFiles(files, into: staging, downloadID: downloadID)
        case let .archive(archive):
            let archiveURL = staging.appendingPathComponent(archive.localFileName)
            try await download(
                archive.remoteURL,
                to: archiveURL,
                expectedSHA256: archive.sha256
            ) { [weak self] progress in
                Task { @MainActor in
                    guard self?.downloadID == downloadID else { return }
                    self?.state = .downloading(progress)
                }
            }
            try Task.checkCancellation()
            try Self.extractArchive(at: archiveURL, into: staging)
        }

        let extractedRoot = staging.appendingPathComponent(model.storageDirectoryName)
        guard fileManager.fileExists(atPath: extractedRoot.path) else {
            throw SpeechModelError.missingDownload
        }

        let targetDirectory = directory(for: model)
        let replacement = modelsRootDirectory.appendingPathComponent(".\(model.storageDirectoryName)-\(UUID().uuidString)", isDirectory: true)

        if case let .files(files) = model.downloadSource {
            try fileManager.createDirectory(at: replacement, withIntermediateDirectories: true)
            for file in files {
                try fileManager.moveItem(
                    at: staging.appendingPathComponent(file.localFileName),
                    to: replacement.appendingPathComponent(file.localFileName)
                )
            }
        } else {
            try fileManager.moveItem(at: extractedRoot, to: replacement)
        }

        try fileManager.createDirectory(at: modelsRootDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.removeItem(at: targetDirectory)
            try fileManager.moveItem(at: replacement, to: targetDirectory)
        } else {
            try fileManager.moveItem(at: replacement, to: targetDirectory)
        }
    }

    private func downloadFiles(
        _ files: [SpeechModelDownloadFile],
        into staging: URL,
        downloadID: UUID
    ) async throws {
        for (index, file) in files.enumerated() {
            let destination = staging.appendingPathComponent(file.localFileName)
            try await download(
                file.remoteURL,
                to: destination,
                expectedSHA256: file.sha256
            ) { [weak self] progress in
                Task { @MainActor in
                    guard self?.downloadID == downloadID else { return }
                    let baseProgress = Double(index) / Double(max(files.count, 1))
                    let stepProgress = progress / Double(max(files.count, 1))
                    self?.state = .downloading(baseProgress + stepProgress)
                }
            }
            try Task.checkCancellation()
        }
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

    private nonisolated static func extractArchive(at archiveURL: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archiveURL.path, "-C", destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SpeechModelError.extractionFailed(message)
        }
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
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return L10n.speechModelChecksumFailed
        case .missingDownload:
            return L10n.speechModelDownloadFailed
        case let .extractionFailed(message):
            return message.isEmpty ? L10n.speechModelDownloadFailed : message
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
