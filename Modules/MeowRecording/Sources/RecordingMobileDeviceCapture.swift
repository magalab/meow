import AVFoundation
import Foundation

public enum RecordingMobileDeviceCaptureFailure: Sendable {
    case unavailable
    case invalidConfiguration
}

public struct RecordingMobileDeviceResult: Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let hasAudio: Bool
}

public final class RecordingMobileDeviceCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let deviceID: String
    private let outputURL: URL
    private let findDevice: (String) -> AVCaptureDevice?
    private let makeFailure: @Sendable (RecordingMobileDeviceCaptureFailure) -> Error
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RecordingMobileDeviceResult, Error>?
    private var stopTimeoutTask: Task<Void, Never>?

    public init(
        deviceID: String,
        outputURL: URL,
        findDevice: @escaping (String) -> AVCaptureDevice?,
        makeFailure: @escaping @Sendable (RecordingMobileDeviceCaptureFailure) -> Error
    ) {
        self.deviceID = deviceID
        self.outputURL = outputURL
        self.findDevice = findDevice
        self.makeFailure = makeFailure
    }

    public func start() throws {
        guard let device = findDevice(deviceID) else {
            throw makeFailure(.unavailable)
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw makeFailure(.invalidConfiguration)
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            throw makeFailure(.invalidConfiguration)
        }
        session.addOutput(output)
        session.startRunning()
        output.startRecording(to: outputURL, recordingDelegate: self)
    }

    public func stop() async throws -> RecordingMobileDeviceResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }
            stopTimeoutTask?.cancel()
            stopTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.resumeStop(throwing: self.makeFailure(.unavailable))
            }
            output.stopRecording()
        }
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        session.stopRunning()
        if let error {
            resumeStop(throwing: error)
            return
        }
        let pending = takeContinuation()
        Task {
            let asset = AVURLAsset(url: outputFileURL)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            let size = (try? await videoTracks.first?.load(.naturalSize)) ?? .zero
            pending?.resume(returning: RecordingMobileDeviceResult(
                fileURL: outputFileURL,
                duration: duration,
                width: Int(abs(size.width)),
                height: Int(abs(size.height)),
                hasAudio: !audioTracks.isEmpty
            ))
        }
    }

    private func takeContinuation() -> CheckedContinuation<RecordingMobileDeviceResult, Error>? {
        lock.withLock {
            let pending = continuation
            continuation = nil
            stopTimeoutTask?.cancel()
            stopTimeoutTask = nil
            return pending
        }
    }

    private func resumeStop(throwing error: Error) {
        session.stopRunning()
        takeContinuation()?.resume(throwing: error)
    }
}
