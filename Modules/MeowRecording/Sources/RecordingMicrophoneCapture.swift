import AVFoundation
import CoreMedia
import Foundation
import os

public enum RecordingMicrophoneCaptureFailure: Sendable {
    case unavailable
    case invalidConfiguration
}

public final class RecordingMicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let deviceID: String
    private let queue: DispatchQueue
    private let handler: (CMSampleBuffer, Float?) -> Void
    private let onIssue: @Sendable () -> Void
    private let findDevice: (String) -> AVCaptureDevice?
    private let makeFailure: (RecordingMicrophoneCaptureFailure) -> Error
    private let session = AVCaptureSession()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "tech.lury.meow", category: "Recording")
    private var lastLevelUpdate = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    public init(
        deviceID: String,
        queue: DispatchQueue,
        findDevice: @escaping (String) -> AVCaptureDevice?,
        makeFailure: @escaping (RecordingMicrophoneCaptureFailure) -> Error,
        handler: @escaping (CMSampleBuffer, Float?) -> Void,
        onIssue: @escaping @Sendable () -> Void
    ) {
        self.deviceID = deviceID
        self.queue = queue
        self.findDevice = findDevice
        self.makeFailure = makeFailure
        self.handler = handler
        self.onIssue = onIssue
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
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw makeFailure(.invalidConfiguration)
        }
        session.addOutput(output)
        session.startRunning()
        guard session.isRunning else {
            throw makeFailure(.unavailable)
        }
        observers = [
            NotificationCenter.default.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [onIssue] _ in onIssue() },
            NotificationCenter.default.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [onIssue, logger] notification in
                if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error {
                    logger.error(
                        "Microphone capture interrupted: \(error.localizedDescription, privacy: .public)"
                    )
                }
                onIssue()
            },
        ]
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if session.isRunning {
            session.stopRunning()
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) >= 0.1 else {
            handler(sampleBuffer, nil)
            return
        }
        lastLevelUpdate = now
        let decibels = connection.audioChannels.map(\.averagePowerLevel).max() ?? -60
        let level = decibels.isFinite ? min(1, max(0, (decibels + 60) / 60)) : 0
        handler(sampleBuffer, level)
    }
}
