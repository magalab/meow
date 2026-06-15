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
    @Published private(set) var state: TtsModelState = .notInstalled
    @Published private(set) var selectedModel: TtsModelKind = .matchaChineseEnglish

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
        directory(for: selectedModel)
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
        cancelDownload()
        try? FileManager.default.removeItem(at: modelDirectory)
        state = .notInstalled
    }

    func openModelFolder() {
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(modelDirectory)
    }

    func configurationDirectory(for model: TtsModelKind) -> URL? {
        let directory = directory(for: model)
        return isInstalled(for: model) ? directory : nil
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private func directory(for model: TtsModelKind) -> URL {
        modelsRootDirectory.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
    }

    private func isInstalled(for model: TtsModelKind) -> Bool {
        let directory = directory(for: model)
        return model.requiredRelativePaths.allSatisfy { relativePath in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }

    private func performDownload(for model: TtsModelKind, downloadID: UUID) async throws {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("Meow-TTS-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let archive = model.archive
        let archiveURL = staging.appendingPathComponent(archive.fileName)
        try await download(
            archive.remoteURL,
            to: archiveURL,
            expectedSHA256: archive.sha256
        ) { [weak self] progress in
            Task { @MainActor in
                guard self?.downloadID == downloadID else { return }
                self?.state = .downloading(progress * 0.92)
            }
        }
        try Task.checkCancellation()
        try await Task.detached(priority: .utility) {
            try Self.extractArchive(at: archiveURL, into: staging)
        }.value
        try Task.checkCancellation()

        let extractedRoot = staging.appendingPathComponent(model.storageDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: extractedRoot.path),
              model.requiredRelativePaths.allSatisfy({
                  $0 == "vocos-16khz-univ.onnx" ||
                      fileManager.fileExists(atPath: extractedRoot.appendingPathComponent($0).path)
              })
        else {
            throw TtsModelError.missingDownload
        }

        for (index, file) in model.additionalFiles.enumerated() {
            let targetURL = extractedRoot.appendingPathComponent(file.relativePath)
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await download(
                file.remoteURL,
                to: targetURL,
                expectedSHA256: file.sha256
            ) { [weak self] progress in
                Task { @MainActor in
                    guard self?.downloadID == downloadID else { return }
                    let base = 0.92
                    let span = 0.06 / Double(max(model.additionalFiles.count, 1))
                    self?.state = .downloading(base + (Double(index) + progress) * span)
                }
            }
            try Task.checkCancellation()
        }

        guard model.requiredRelativePaths.allSatisfy({
            fileManager.fileExists(atPath: extractedRoot.appendingPathComponent($0).path)
        }) else {
            throw TtsModelError.missingDownload
        }

        state = .downloading(0.98)
        try fileManager.createDirectory(at: modelsRootDirectory, withIntermediateDirectories: true)
        let target = directory(for: model)
        let replacement = modelsRootDirectory
            .appendingPathComponent(".\(model.storageDirectoryName)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: extractedRoot, to: replacement)
        defer { try? fileManager.removeItem(at: replacement) }
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: replacement)
        } else {
            try fileManager.moveItem(at: replacement, to: target)
        }
    }

    private nonisolated func download(
        _ remoteURL: URL,
        to destinationURL: URL,
        expectedSHA256: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = TtsDownloadDelegate(progress: progress)
        let temporaryURL = try await delegate.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try Task.checkCancellation()

        if let expectedSHA256 {
            let digest = try Self.sha256(of: temporaryURL)
            guard digest == expectedSHA256 else {
                throw TtsModelError.checksumMismatch
            }
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
            throw TtsModelError.extractionFailed(message)
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

private enum TtsModelError: LocalizedError {
    case checksumMismatch
    case missingDownload
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return L10n.ttsModelChecksumFailed
        case .missingDownload:
            return L10n.ttsModelDownloadFailed
        case let .extractionFailed(message):
            return message.isEmpty ? L10n.ttsModelDownloadFailed : message
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
            return
        }
        lock.lock()
        let downloadedURL = self.downloadedURL
        lock.unlock()
        if let downloadedURL {
            finish(.success(downloadedURL))
        } else {
            finish(.failure(TtsModelError.missingDownload))
        }
    }

    private func cancel() {
        let values = takePendingValues(markFinished: true)
        values.session?.invalidateAndCancel()
        if let downloadedURL = values.downloadedURL {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
        values.continuation?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            if case let .success(url) = result {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        lock.unlock()

        let values = takePendingValues(markFinished: true)
        values.session?.finishTasksAndInvalidate()
        if case .failure = result, let downloadedURL = values.downloadedURL {
            try? FileManager.default.removeItem(at: downloadedURL)
        }
        values.continuation?.resume(with: result)
    }

    private func takePendingValues(
        markFinished: Bool
    ) -> (
        session: URLSession?,
        continuation: CheckedContinuation<URL, Error>?,
        downloadedURL: URL?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return (nil, nil, nil) }
        isFinished = markFinished
        let values = (session, continuation, downloadedURL)
        session = nil
        continuation = nil
        downloadedURL = nil
        return values
    }
}
