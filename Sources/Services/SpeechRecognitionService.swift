import AppKit
@preconcurrency import AVFAudio
import AVFoundation
import Foundation

enum SpeechPermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var state: SpeechRecognitionState = .idle
    @Published private(set) var permissionState: SpeechPermissionState = .notDetermined

    var onNeedsModel: (() -> Void)?
    var onStateChanged: ((SpeechRecognitionState) -> Void)?

    private let modelStore: SpeechModelStore
    private let historyStore: SpeechHistoryStore
    private let clipboardStore: ClipboardStore
    private let recognitionEngine = SpeechRecognitionEngine()
    private let audioEngine = AVAudioEngine()

    private var captureContext: SpeechCaptureContext?
    private var isInputTapInstalled = false
    private var durationTimer: Timer?
    private var recognitionTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var isHotkeyHeld = false
    private var currentSettings = SpeechSettings.default

    init(
        modelStore: SpeechModelStore,
        historyStore: SpeechHistoryStore,
        clipboardStore: ClipboardStore
    ) {
        self.modelStore = modelStore
        self.historyStore = historyStore
        self.clipboardStore = clipboardStore
        refreshPermissionState()
    }

    func apply(settings: SpeechSettings) {
        if currentSettings.model != settings.model {
            Task { await recognitionEngine.unload() }
        }
        currentSettings = settings
        historyStore.cleanup(retentionDays: settings.retentionDays)
        if !settings.enabled {
            cancel()
        }
    }

    func refreshPermissionState() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionState = .granted
        case .denied, .restricted:
            permissionState = .denied
        case .notDetermined:
            permissionState = .notDetermined
        @unknown default:
            permissionState = .denied
        }
    }

    func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionState = .granted
        case .notDetermined:
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard let self else { return }
                self.permissionState = granted ? .granted : .denied
            }
        case .denied, .restricted:
            permissionState = .denied
            openMicrophonePrivacySettings()
        @unknown default:
            permissionState = .denied
        }
    }

    func hotkeyPressed() {
        guard currentSettings.enabled, !state.isActive else { return }
        isHotkeyHeld = true
        resetTask?.cancel()

        guard modelStore.isInstalled else {
            setTransientState(.needsModel)
            onNeedsModel?()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionState = .granted
            startRecordingIfHeld()
        case .notDetermined:
            permissionState = .notDetermined
            setState(.requestingPermission)
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard let self else { return }
                self.permissionState = granted ? .granted : .denied
                if granted {
                    self.startRecordingIfHeld()
                } else {
                    self.isHotkeyHeld = false
                    self.setFailure(L10n.speechPermissionDenied)
                }
            }
        case .denied, .restricted:
            permissionState = .denied
            isHotkeyHeld = false
            setFailure(L10n.speechPermissionDenied)
        @unknown default:
            permissionState = .denied
            isHotkeyHeld = false
            setFailure(L10n.speechPermissionDenied)
        }
    }

    func hotkeyReleased() {
        isHotkeyHeld = false
        switch state {
        case .recording:
            finishRecording()
        case .requestingPermission:
            setState(.idle)
        default:
            break
        }
    }

    func cancel() {
        isHotkeyHeld = false
        recognitionTask?.cancel()
        recognitionTask = nil
        resetTask?.cancel()
        Task { await recognitionEngine.unload() }
        stopAudioEngine()
        if state != .idle {
            setTransientState(.cancelled)
        }
    }

    func unloadModel() {
        Task { await recognitionEngine.unload() }
    }

    func openMicrophonePrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func startRecordingIfHeld() {
        guard isHotkeyHeld else {
            setState(.idle)
            return
        }

        do {
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  inputFormat.channelCount > 0,
                  let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 16_000,
                    channels: 1,
                    interleaved: false
                  ),
                  let context = SpeechCaptureContext(inputFormat: inputFormat, outputFormat: outputFormat)
            else {
                throw SpeechRecordingError.invalidAudioFormat
            }

            captureContext = context
            let limitNotifier = SpeechRecordingLimitNotifier { [weak self] in
                guard let self, case .recording = self.state else { return }
                self.isHotkeyHeld = false
                self.finishRecording()
            }
            inputNode.installTap(
                onBus: 0,
                bufferSize: 2048,
                format: inputFormat,
                block: Self.makeAudioTapBlock(context: context, limitNotifier: limitNotifier)
            )
            isInputTapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            playSound(named: "Tink")
            setState(.recording(0))
            startDurationTimer()
        } catch {
            stopAudioEngine()
            setFailure(error.localizedDescription)
        }
    }

    private func finishRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        stopAudioEngine(removeContext: false)

        guard let context = captureContext else {
            setFailure(L10n.speechRecordingFailed)
            return
        }
        captureContext = nil
        let samples = context.snapshot()
        let duration = Double(samples.count) / 16_000
        guard samples.count >= 1_600 else {
            setFailure(L10n.speechTooShort)
            return
        }

        playSound(named: "Pop")
        setState(.transcribing)
        let model = currentSettings.model
        let modelURL = modelStore.modelURL
        let tokensURL = modelStore.tokensURL
        let settings = currentSettings

        recognitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recognitionEngine.recognize(
                    samples: samples,
                    model: model,
                    modelURL: modelURL,
                    tokensURL: tokensURL
                )
                try Task.checkCancellation()
                do {
                    try self.historyStore.append(
                        text: result.text,
                        language: result.language,
                        duration: duration,
                        samples: samples,
                        retentionDays: settings.retentionDays
                    )
                } catch {
                    NSLog("[Meow] Failed to save speech history: \(error.localizedDescription)")
                }
                try Task.checkCancellation()
                let pasted = self.clipboardStore.performTemporaryTextPaste(result.text)
                self.setTransientState(pasted ? .pasted : .copied)
            } catch is CancellationError {
                self.setTransientState(.cancelled)
            } catch {
                self.setFailure(error.localizedDescription)
            }
            self.recognitionTask = nil
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let captureContext = self.captureContext else { return }
                self.setState(.recording(captureContext.duration))
            }
        }
    }

    private func stopAudioEngine(removeContext: Bool = true) {
        durationTimer?.invalidate()
        durationTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isInputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isInputTapInstalled = false
        }
        if removeContext {
            captureContext = nil
        }
    }

    private func playSound(named name: NSSound.Name) {
        guard currentSettings.soundEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func setFailure(_ message: String) {
        setTransientState(.failed(message))
    }

    private func setTransientState(_ newState: SpeechRecognitionState) {
        setState(newState)
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.recognitionEngine.unload()
            self?.setState(.idle)
        }
    }

    private func setState(_ newState: SpeechRecognitionState) {
        state = newState
        onStateChanged?(newState)
    }

    private nonisolated static func makeAudioTapBlock(
        context: SpeechCaptureContext,
        limitNotifier: SpeechRecordingLimitNotifier
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            if context.consume(buffer) {
                limitNotifier.notify()
            }
        }
    }
}

private enum SpeechRecordingError: LocalizedError {
    case invalidAudioFormat

    var errorDescription: String? {
        L10n.speechRecordingFailed
    }
}

private final class SpeechCaptureContext: @unchecked Sendable {
    private static let maximumSampleCount = 16_000 * 30

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var samples: [Float] = []
    private var reachedLimit = false

    init?(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.outputFormat = outputFormat
        samples.reserveCapacity(16_000 * 30)
    }

    var duration: TimeInterval {
        lock.withLock { Double(samples.count) / 16_000 }
    }

    func consume(_ inputBuffer: AVAudioPCMBuffer) -> Bool {
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return false
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outputStatus in
            if suppliedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }
        guard conversionError == nil,
              status != .error,
              outputBuffer.frameLength > 0,
              let channel = outputBuffer.floatChannelData?[0]
        else {
            return false
        }

        let values = UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength))
        return lock.withLock {
            guard !reachedLimit else { return false }
            let remaining = Self.maximumSampleCount - samples.count
            samples.append(contentsOf: values.prefix(remaining))
            reachedLimit = samples.count >= Self.maximumSampleCount
            return reachedLimit
        }
    }

    func snapshot() -> [Float] {
        lock.withLock { samples }
    }
}

private final class SpeechRecordingLimitNotifier: @unchecked Sendable {
    private let action: @MainActor @Sendable () -> Void

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    nonisolated func notify() {
        Task { @MainActor [action] in
            action()
        }
    }
}

private actor SpeechRecognitionEngine {
    private var recognizer: SherpaOnnxRecognizer?
    private var loadedModel: SpeechModelKind?

    func recognize(
        samples: [Float],
        model: SpeechModelKind,
        modelURL: URL,
        tokensURL: URL
    ) throws -> SpeechRecognitionResult {
        try Task.checkCancellation()
        if recognizer == nil || loadedModel != model {
            recognizer = try SherpaOnnxRecognizer(model: model, modelURL: modelURL, tokensURL: tokensURL)
            loadedModel = model
        }
        let result = try recognizer!.recognize(samples: samples, sampleRate: 16_000)
        try Task.checkCancellation()
        return result
    }

    func unload() async {
        recognizer = nil
        loadedModel = nil
    }
}
