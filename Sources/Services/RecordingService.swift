import AppKit
import AVFoundation
import CoreMedia
import CoreMediaIO
import ImageIO
import Foundation
import IOKit.pwr_mgt
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

enum RecordingError: LocalizedError {
    case permissionDenied
    case sourceUnavailable
    case alreadyRecording
    case invalidConfiguration
    case writerFailed(String)
    case microphoneDenied
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Screen Recording permission is required."
        case .sourceUnavailable: return "The selected recording source is no longer available."
        case .alreadyRecording: return "A recording is already in progress."
        case .invalidConfiguration: return "The selected recording configuration is not supported."
        case let .writerFailed(message): return message
        case .microphoneDenied: return "Microphone permission is required for this recording."
        case .insufficientDiskSpace: return "There is not enough free disk space to start recording."
        }
    }
}

@MainActor
final class RecordingService: NSObject, ObservableObject {
    @Published private(set) var state: RecordingState = .idle {
        didSet { onStateChanged?(state, elapsed) }
    }
    @Published private(set) var elapsed: TimeInterval = 0 {
        didSet { onStateChanged?(state, elapsed) }
    }
    @Published private(set) var lastArtifact: RecordingArtifact?

    var onCompleted: ((RecordingArtifact) -> Void)?
    var onError: ((Error) -> Void)?
    var onStateChanged: ((RecordingState, TimeInterval) -> Void)?

    private let store: RecordingStore
    private var settings = RecordingSettings.default
    private var preparedSource: RecordingSource?
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var microphoneCapture: RecordingMicrophoneCapture?
    private var mobileCapture: RecordingMobileDeviceCapture?
    private var countdownTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0

    init(store: RecordingStore) {
        self.store = store
        super.init()
    }

    func apply(settings: RecordingSettings) {
        self.settings = settings.normalized()
        store.applyRetentionPolicy(
            historyLimit: settings.historyLimit,
            retentionDays: settings.retentionDays,
            maxStorageMB: settings.maxStorageMB
        )
    }

    func prepare(source: RecordingSource) throws {
        guard !state.isActive else { throw RecordingError.alreadyRecording }
        preparedSource = source
        state = .preparing
    }

    func start() async throws {
        guard let source = preparedSource else { throw RecordingError.sourceUnavailable }
        settings = settings.normalized(for: source.kind)
        if source.kind != .mobileDevice {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                throw RecordingError.permissionDenied
            }
        }
        if settings.audioMode.capturesMicrophone {
            let granted = await requestMicrophonePermission()
            guard granted else { throw RecordingError.microphoneDenied }
        }

        if settings.countdownSeconds > 0 {
            for remaining in stride(from: settings.countdownSeconds, through: 1, by: -1) {
                state = .countdown(remaining)
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
            }
        }
        try await beginCapture(source: source)
    }

    func start(source: RecordingSource) async {
        do {
            try prepare(source: source)
            try await start()
        } catch {
            fail(error)
        }
    }

    func pause() {
        guard case .recording = state else { return }
        writer?.setPaused(true)
        stopElapsedTimer()
        state = .paused(elapsed: elapsed)
    }

    func resume() {
        guard case .paused = state else { return }
        writer?.setPaused(false)
        state = .recording(startedAt: Date().addingTimeInterval(-elapsed))
        startElapsedTimer()
    }

    func pauseOrResume() {
        if case .paused = state {
            resume()
        } else {
            pause()
        }
    }

    func stop() async {
        guard state.isActive else { return }
        state = .finishing
        stopElapsedTimer()
        countdownTask?.cancel()
        countdownTask = nil

        if let stream {
            try? await stream.stopCapture()
        }
        self.stream = nil
        microphoneCapture?.stop()
        microphoneCapture = nil
        allowSleep()

        if let mobileCapture {
            self.mobileCapture = nil
            do {
                let result = try await mobileCapture.stop()
                let artifact = await store.add(
                    fileURL: result.fileURL,
                    source: .mobileDevice,
                    duration: result.duration,
                    width: result.width,
                    height: result.height,
                    codec: nil,
                    hasSystemAudio: result.hasAudio,
                    hasMicrophoneAudio: false
                )
                store.markRecordingFinished(fileURL: result.fileURL)
                lastArtifact = artifact
                state = .idle
                preparedSource = nil
                elapsed = 0
                onCompleted?(artifact)
            } catch {
                fail(error)
            }
            return
        }

        guard let writer else {
            reset()
            return
        }
        self.writer = nil
        do {
            let result = try await writer.finish()
            let artifact = await store.add(
                fileURL: result.fileURL,
                source: result.source,
                duration: result.duration,
                width: result.width,
                height: result.height,
                codec: result.codec,
                hasSystemAudio: result.hasSystemAudio,
                hasMicrophoneAudio: result.hasMicrophoneAudio
            )
            store.markRecordingFinished(fileURL: result.fileURL)
            lastArtifact = artifact
            state = .idle
            preparedSource = nil
            elapsed = 0
            onCompleted?(artifact)
        } catch {
            fail(error)
        }
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        if case .countdown = state {
            reset()
        } else if state.isActive {
            Task { await stop() }
        }
    }

    func saveCurrentFrame() async throws -> URL {
        guard let image = writer?.latestFrame else {
            throw RecordingError.sourceUnavailable
        }
        let directory = frameOutputDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueFrameURL(in: directory)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RecordingError.writerFailed("The current frame could not be encoded.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RecordingError.writerFailed("The current frame could not be encoded.")
        }
        return url
    }

    static func capabilities() -> RecordingCapabilities {
        enableExternalCaptureDevices()
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let hasCamera = !discovery.devices.isEmpty
        return RecordingCapabilities(
            supportsHEVC: Self.supportsHardwareEncoder(codec: kCMVideoCodecType_HEVC),
            supportsHEVCWithAlpha: Self.supportsHardwareEncoder(codec: kCMVideoCodecType_HEVCWithAlpha),
            supportsHDR: Self.supportsHardwareEncoder(codec: kCMVideoCodecType_HEVC),
            supportsPresenterOverlay: hasCamera,
            hasCamera: hasCamera,
            hasMicrophone: !microphones.devices.isEmpty,
            hasMobileCaptureDevice: !mobileDevices().isEmpty
        )
    }

    nonisolated static func mobileDevices() -> [AVCaptureDevice] {
        enableExternalCaptureDevices()
        let muxed = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .muxed,
            position: .unspecified
        ).devices
        let video = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices
        var seen = Set<String>()
        return (muxed + video).filter { seen.insert($0.uniqueID).inserted }
    }

    nonisolated static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func beginCapture(source: RecordingSource) async throws {
        let outputURL = try RecordingStore.outputURL(settings: settings, source: source.kind)
        if let available = RecordingStore.availableCapacity(at: outputURL.deletingLastPathComponent()),
           available < 512 * 1_024 * 1_024
        {
            throw RecordingError.insufficientDiskSpace
        }
        if case let .mobileDevice(deviceID) = source {
            store.markRecordingStarted(fileURL: outputURL, source: source.kind)
            let capture = RecordingMobileDeviceCapture(
                deviceID: deviceID,
                outputURL: outputURL
            )
            try capture.start()
            mobileCapture = capture
            if settings.preventSleep {
                preventSleep()
            }
            state = .recording(startedAt: Date())
            elapsed = 0
            startElapsedTimer()
            return
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let configuration = try makeConfiguration(for: source)
        let filter = makeFilter(for: source, content: content)
        store.markRecordingStarted(fileURL: outputURL, source: source.kind)
        let writer = try RecordingWriter(
            outputURL: outputURL,
            source: source.kind,
            configuration: configuration,
            settings: settings,
            onStreamStopped: { [weak self] error in
                Task { @MainActor in
                    await self?.handleUnexpectedStreamStop(error)
                }
            }
        )
        self.writer = writer

        let stream = SCStream(filter: filter, configuration: configuration, delegate: writer)
        try stream.addStreamOutput(
            writer,
            type: SCStreamOutputType.screen,
            sampleHandlerQueue: writer.queue
        )
        if settings.audioMode.capturesSystemAudio {
            try stream.addStreamOutput(
                writer,
                type: SCStreamOutputType.audio,
                sampleHandlerQueue: writer.queue
            )
        }
        self.stream = stream

        if settings.audioMode.capturesMicrophone {
            let microphone = RecordingMicrophoneCapture(
                deviceID: settings.microphoneDeviceID,
                queue: writer.queue
            ) { [weak writer] sampleBuffer in
                writer?.appendMicrophone(sampleBuffer)
            }
            try microphone.start()
            microphoneCapture = microphone
        }

        try await stream.startCapture()
        if settings.preventSleep {
            preventSleep()
        }
        state = .recording(startedAt: Date())
        elapsed = 0
        startElapsedTimer()
    }

    private func makeFilter(
        for source: RecordingSource,
        content: SCShareableContent
    ) -> SCContentFilter {
        switch source {
        case let .display(display), let .region(display, _, _), let .systemAudio(display):
            var excludedBundleIDs = Set(settings.excludedApplicationBundleIDs.map { $0.lowercased() })
            if settings.excludeMeow, let bundleID = Bundle.main.bundleIdentifier {
                excludedBundleIDs.insert(bundleID.lowercased())
            }
            let overlayTitles = Set([
                CameraOverlayController.windowTitle,
                ScreenMagnifierController.windowTitle,
            ])
            let systemOverlayBundleIDs: Set<String> = [
                "com.apple.controlcenter",
                "com.apple.notificationcenterui",
                "com.apple.dock",
                "com.apple.systemuiserver",
            ]
            let excludedWindows = content.windows.filter { window in
                let bundleID = window.owningApplication?.bundleIdentifier.lowercased() ?? ""
                if overlayTitles.contains(window.title ?? "") {
                    return false
                }
                if excludedBundleIDs.contains(bundleID) {
                    return true
                }
                if settings.excludeSystemOverlays, systemOverlayBundleIDs.contains(bundleID) {
                    return true
                }
                return settings.excludeDesktopIcons
                    && bundleID == "com.apple.finder"
                    && (window.title?.isEmpty ?? true)
            }
            let filter = SCContentFilter(
                display: display,
                excludingWindows: excludedWindows
            )
            filter.includeMenuBar = settings.includeMenuBar
            return filter
        case let .window(window):
            return SCContentFilter(desktopIndependentWindow: window)
        case let .application(application, display):
            return SCContentFilter(display: display, including: [application], exceptingWindows: [])
        case let .contentFilter(filter):
            return filter
        case .mobileDevice:
            preconditionFailure("Mobile devices do not use ScreenCaptureKit")
        }
    }

    private func makeConfiguration(for source: RecordingSource) throws -> SCStreamConfiguration {
        let configuration = settings.recordHDR
            ? SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay)
            : SCStreamConfiguration()
        let dimensions: (width: CGFloat, height: CGFloat, scale: CGFloat)
        switch source {
        case let .display(display), let .systemAudio(display):
            let scale = ScreenCaptureService.screen(for: display.displayID)?.backingScaleFactor ?? 1
            dimensions = (CGFloat(display.width), CGFloat(display.height), scale)
        case let .region(display, rect, scale):
            dimensions = (rect.width, rect.height, scale)
            let displayHeight = CGFloat(display.height) / max(1, scale)
            configuration.sourceRect = CGRect(
                x: rect.minX,
                y: displayHeight - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        case let .window(window):
            dimensions = (window.frame.width, window.frame.height, 1)
        case let .application(_, display):
            let scale = ScreenCaptureService.screen(for: display.displayID)?.backingScaleFactor ?? 1
            dimensions = (CGFloat(display.width), CGFloat(display.height), scale)
        case let .contentFilter(filter):
            dimensions = (
                filter.contentRect.width,
                filter.contentRect.height,
                CGFloat(filter.pointPixelScale)
            )
        case .mobileDevice:
            throw RecordingError.invalidConfiguration
        }
        let scale = settings.captureRetinaResolution ? dimensions.scale : 1
        configuration.width = max(2, Int((dimensions.width * scale).rounded()) & ~1)
        configuration.height = max(2, Int((dimensions.height * scale).rounded()) & ~1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, settings.frameRate)))
        configuration.queueDepth = 6
        configuration.presenterOverlayPrivacyAlertSetting = .system
        configuration.showsCursor = settings.showCursor
        configuration.showMouseClicks = settings.highlightMouseClicks
        if settings.videoCodec == .hevcWithAlpha || settings.backgroundStyle == .transparent {
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.backgroundColor = NSColor.clear.cgColor
        } else if settings.backgroundStyle == .solidColor {
            configuration.backgroundColor = Self.color(
                hex: settings.backgroundColorHex
            ).cgColor
        }
        configuration.capturesAudio = settings.audioMode.capturesSystemAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        return configuration
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func frameOutputDirectory() -> URL {
        if settings.saveDirectory.isEmpty {
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Meow", isDirectory: true)
        }
        return URL(fileURLWithPath: NSString(string: settings.saveDirectory).expandingTildeInPath)
    }

    private func uniqueFrameURL(in directory: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = RecordingStore.expandedFileName(
            template: "Meow Recording Frame yyyy-MM-dd HH.mm.ss"
        )
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }
        return candidate
    }

    private func handleUnexpectedStreamStop(_ error: Error) async {
        guard state.isActive else { return }
        await stop()
        onError?(RecordingError.writerFailed(
            "Recording ended unexpectedly. Meow kept the playable portion when possible: \(error.localizedDescription)"
        ))
    }

    private static func color(hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return NSColor(calibratedWhite: 0.1, alpha: 1)
        }
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let writer = self.writer {
                    self.elapsed = writer.duration
                } else if case let .recording(startedAt) = self.state {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func preventSleep() {
        guard sleepAssertionID == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Meow screen recording" as CFString,
            &sleepAssertionID
        )
    }

    private func allowSleep() {
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }

    private func fail(_ error: Error) {
        stopElapsedTimer()
        allowSleep()
        state = .failed(error.localizedDescription)
        preparedSource = nil
        onError?(error)
    }

    private func reset() {
        state = .idle
        preparedSource = nil
        elapsed = 0
    }

    private static func supportsHardwareEncoder(codec: CMVideoCodecType) -> Bool {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 64,
            height: 64,
            codecType: codec,
            encoderSpecification: [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
            ] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        return status == noErr
    }

    nonisolated private static func enableExternalCaptureDevices() {
        var allow: UInt32 = 1
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )
    }
}

private struct RecordingWriterResult {
    let fileURL: URL
    let source: RecordingSourceKind
    let duration: TimeInterval
    let width: Int
    let height: Int
    let codec: RecordingVideoCodec?
    let hasSystemAudio: Bool
    let hasMicrophoneAudio: Bool
}

private final class RecordingWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private enum SampleKind {
        case video
        case audio
    }

    private enum SampleSource {
        case video
        case systemAudio
        case microphone

        var kind: SampleKind {
            switch self {
            case .video: return .video
            case .systemAudio, .microphone: return .audio
            }
        }
    }

    let queue = DispatchQueue(label: "tech.lury.meow.recording.writer", qos: .userInitiated)

    private let outputURL: URL
    private let source: RecordingSourceKind
    private let settings: RecordingSettings
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput?
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let onStreamStopped: @Sendable (Error) -> Void
    private var sessionStarted = false
    private var videoStartPTS: CMTime?
    private var systemAudioStartPTS: CMTime?
    private var microphoneStartPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var lastSystemAudioPTS: CMTime?
    private var lastMicrophonePTS: CMTime?
    private var pausedAt: CMTime?
    private var timeOffset = CMTime.zero
    private var isPaused = false
    private let ciContext = CIContext()
    private var latestFrameStorage: CGImage?

    var duration: TimeInterval {
        queue.sync {
            self.durationOnQueue
        }
    }

    var latestFrame: CGImage? {
        queue.sync {
            latestFrameStorage
        }
    }

    init(
        outputURL: URL,
        source: RecordingSourceKind,
        configuration: SCStreamConfiguration,
        settings: RecordingSettings,
        onStreamStopped: @escaping @Sendable (Error) -> Void
    ) throws {
        self.outputURL = outputURL
        self.source = source
        self.settings = settings
        self.onStreamStopped = onStreamStopped
        let outputFileType: AVFileType
        if source == .systemAudio {
            outputFileType = settings.audioFormat == .aac || settings.audioFormat == .alac
                ? .m4a
                : .caf
        } else if settings.audioMode == .systemAndMicrophone {
            outputFileType = .mov
        } else {
            outputFileType = settings.videoFormat == .mp4 ? .mp4 : .mov
        }
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: outputFileType)

        if source == .systemAudio {
            videoInput = nil
        } else {
            let codec: AVVideoCodecType
            switch settings.videoCodec {
            case .h264: codec = .h264
            case .hevc: codec = .hevc
            case .hevcWithAlpha: codec = .hevcWithAlpha
            }
            let pixels = Double(configuration.width * configuration.height)
            let bitrate = max(500_000, Int(pixels * Double(settings.frameRate) * settings.quality.bitrateMultiplier))
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: settings.frameRate,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
            ]
            var videoSettings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: configuration.width,
                AVVideoHeightKey: configuration.height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            if settings.recordHDR {
                compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel
                videoSettings[AVVideoCompressionPropertiesKey] = compression
                videoSettings[AVVideoColorPropertiesKey] = [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                ]
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw RecordingError.invalidConfiguration }
            assetWriter.add(input)
            videoInput = input
        }

        if settings.audioMode.capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: Self.audioSettings(
                    format: source == .systemAudio ? settings.audioFormat : .aac
                )
            )
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw RecordingError.invalidConfiguration }
            assetWriter.add(input)
            systemAudioInput = input
        } else {
            systemAudioInput = nil
        }

        if settings.audioMode.capturesMicrophone {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: Self.audioSettings(
                    format: source == .systemAudio ? settings.audioFormat : .aac
                )
            )
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw RecordingError.invalidConfiguration }
            assetWriter.add(input)
            microphoneInput = input
        } else {
            microphoneInput = nil
        }
        super.init()
        guard assetWriter.startWriting() else {
            throw RecordingError.writerFailed(assetWriter.error?.localizedDescription ?? "Unable to start the recording writer.")
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async {
            self.isPaused = paused
            if paused {
                self.pausedAt = self.currentTimelinePTS()
            }
        }
    }

    func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: microphoneInput, source: .microphone, establishesSession: videoInput == nil)
    }

    func finish() async throws -> RecordingWriterResult {
        await withCheckedContinuation { continuation in
            queue.async {
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                self.assetWriter.finishWriting {
                    continuation.resume()
                }
            }
        }
        guard assetWriter.status == .completed else {
            throw RecordingError.writerFailed(assetWriter.error?.localizedDescription ?? "The recording could not be finalized.")
        }
        var finalURL = outputURL
        if settings.audioMode == .systemAndMicrophone,
           !settings.keepAudioTracksSeparate,
           source != .systemAudio
        {
            finalURL = try await RecordingAudioMixer.mixTracks(in: outputURL)
        }
        return RecordingWriterResult(
            fileURL: finalURL,
            source: source,
            duration: duration,
            width: videoInput == nil ? 0 : Int(videoInput?.outputSettings?[AVVideoWidthKey] as? Int ?? 0),
            height: videoInput == nil ? 0 : Int(videoInput?.outputSettings?[AVVideoHeightKey] as? Int ?? 0),
            codec: videoInput == nil ? nil : settings.videoCodec,
            hasSystemAudio: settings.audioMode.capturesSystemAudio,
            hasMicrophoneAudio: settings.audioMode.capturesMicrophone
        )
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }
        if isPaused { return }
        switch outputType {
        case .screen:
            guard isCompleteScreenFrame(sampleBuffer) else { return }
            if let imageBuffer = sampleBuffer.imageBuffer {
                latestFrameStorage = ciContext.createCGImage(
                    CIImage(cvPixelBuffer: imageBuffer),
                    from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(imageBuffer), height: CVPixelBufferGetHeight(imageBuffer))
                )
            }
            append(sampleBuffer, to: videoInput, source: .video, establishesSession: true)
        case .audio:
            append(sampleBuffer, to: systemAudioInput, source: .systemAudio, establishesSession: videoInput == nil)
        case .microphone:
            append(sampleBuffer, to: microphoneInput, source: .microphone, establishesSession: videoInput == nil)
        @unknown default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped(error)
    }

    private func append(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?,
        source: SampleSource,
        establishesSession: Bool
    ) {
        if isPaused { return }
        guard let input, input.isReadyForMoreMediaData else { return }
        let pts = sampleBuffer.presentationTimeStamp
        if establishesSession, !sessionStarted {
            setStartPTS(pts, for: source)
            assetWriter.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
        guard sessionStarted else { return }
        ensureStartPTS(for: source, pts: pts)
        if let pausedAt {
            let timelinePTS = normalizedPTS(for: pts, source: source)
            timeOffset = timeOffset + max(.zero, timelinePTS - pausedAt)
            self.pausedAt = nil
        }
        guard let startPTS = startPTS(for: source) else { return }
        let baseOffset = startPTS + timeOffset
        let adjusted = Self.adjusted(sampleBuffer, by: baseOffset)
        guard let adjusted else { return }
        let adjustedPTS = adjusted.presentationTimeStamp
        if input.append(adjusted) {
            switch source.kind {
            case .video:
                lastVideoPTS = adjustedPTS
            case .audio:
                switch source {
                case .video:
                    break
                case .systemAudio:
                    lastSystemAudioPTS = max(lastSystemAudioPTS ?? .zero, adjustedPTS)
                case .microphone:
                    lastMicrophonePTS = max(lastMicrophonePTS ?? .zero, adjustedPTS)
                }
            }
        }
    }

    private func currentTimelinePTS() -> CMTime {
        [
            lastVideoPTS,
            lastSystemAudioPTS,
            lastMicrophonePTS,
        ].compactMap { $0 }.max() ?? .zero
    }

    private var durationOnQueue: TimeInterval {
        let lastPTS = currentTimelinePTS()
        return max(0, CMTimeGetSeconds(lastPTS))
    }

    private func normalizedPTS(for sourcePTS: CMTime, source: SampleSource) -> CMTime {
        guard let startPTS = startPTS(for: source) else { return .zero }
        return max(.zero, sourcePTS - startPTS - timeOffset)
    }

    private func setStartPTS(_ pts: CMTime, for source: SampleSource) {
        switch source {
        case .video:
            videoStartPTS = pts
        case .systemAudio:
            systemAudioStartPTS = pts
        case .microphone:
            microphoneStartPTS = pts
        }
    }

    private func startPTS(for source: SampleSource) -> CMTime? {
        switch source {
        case .video:
            return videoStartPTS
        case .systemAudio:
            return systemAudioStartPTS
        case .microphone:
            return microphoneStartPTS
        }
    }

    private func ensureStartPTS(for source: SampleSource, pts: CMTime) {
        guard startPTS(for: source) == nil else { return }
        if source == .systemAudio, videoInput != nil, let videoStartPTS {
            systemAudioStartPTS = videoStartPTS
            return
        }
        let timelineAnchor = currentTimelinePTS()
        setStartPTS(pts - timelineAnchor - timeOffset, for: source)
    }

    private func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let statusValue = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: statusValue) == .complete
        else {
            return false
        }
        return true
    }

    private static func adjusted(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        var timing = [CMSampleTimingInfo](repeating: .init(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: count,
            arrayToFill: &timing,
            entriesNeededOut: &count
        )
        for index in timing.indices {
            timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - offset
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - offset
            }
        }
        var output: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timing,
            sampleBufferOut: &output
        )
        return status == noErr ? output : nil
    }

    private static func audioSettings(format: RecordingAudioFormat) -> [String: Any] {
        let formatID: AudioFormatID
        switch format {
        case .aac: formatID = kAudioFormatMPEG4AAC
        case .alac: formatID = kAudioFormatAppleLossless
        case .flac: formatID = kAudioFormatFLAC
        case .opus: formatID = kAudioFormatOpus
        }
        var settings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
        ]
        if format == .aac || format == .opus {
            settings[AVEncoderBitRateKey] = 192_000
        }
        return settings
    }
}

private enum RecordingAudioMixer {
    static func mixTracks(in sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first, audioTracks.count > 1 else {
            return sourceURL
        }
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let duration = videoTimeRange.duration
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingError.invalidConfiguration
        }
        try compositionVideo.insertTimeRange(
            videoTimeRange,
            of: videoTrack,
            at: .zero
        )
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        var mixParameters: [AVMutableAudioMixInputParameters] = []
        for audioTrack in audioTracks {
            guard let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let audioTimeRange = try await audioTrack.load(.timeRange)
            let audioDuration = audioTimeRange.duration
            let insertDuration = min(duration, audioDuration)
            guard insertDuration > .zero else { continue }
            try compositionAudio.insertTimeRange(
                CMTimeRange(start: audioTimeRange.start, duration: insertDuration),
                of: audioTrack,
                at: .zero
            )
            if insertDuration < duration {
                compositionAudio.insertEmptyTimeRange(
                    CMTimeRange(start: insertDuration, duration: duration - insertDuration)
                )
            }
            let parameters = AVMutableAudioMixInputParameters(track: compositionAudio)
            parameters.setVolume(1, at: .zero)
            mixParameters.append(parameters)
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = mixParameters
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecordingError.invalidConfiguration
        }
        exporter.audioMix = mix
        let temporaryURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-mixed")
            .appendingPathExtension(sourceURL.pathExtension)
        let fileType: AVFileType = sourceURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        try await exporter.export(to: temporaryURL, as: fileType)
        _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: temporaryURL)
        return sourceURL
    }
}

private final class RecordingMicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let deviceID: String
    private let queue: DispatchQueue
    private let handler: (CMSampleBuffer) -> Void
    private let session = AVCaptureSession()

    init(deviceID: String, queue: DispatchQueue, handler: @escaping (CMSampleBuffer) -> Void) {
        self.deviceID = deviceID
        self.queue = queue
        self.handler = handler
    }

    func start() throws {
        let device: AVCaptureDevice?
        if deviceID.isEmpty {
            device = AVCaptureDevice.default(for: .audio)
        } else {
            device = RecordingService.microphones().first { $0.uniqueID == deviceID }
        }
        guard let device else { throw RecordingError.sourceUnavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.invalidConfiguration }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecordingError.invalidConfiguration }
        session.addOutput(output)
        session.startRunning()
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        handler(sampleBuffer)
    }
}

private struct RecordingMobileDeviceResult {
    let fileURL: URL
    let duration: TimeInterval
    let width: Int
    let height: Int
    let hasAudio: Bool
}

private final class RecordingMobileDeviceCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let deviceID: String
    private let outputURL: URL
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var continuation: CheckedContinuation<RecordingMobileDeviceResult, Error>?

    init(deviceID: String, outputURL: URL) {
        self.deviceID = deviceID
        self.outputURL = outputURL
    }

    func start() throws {
        guard let device = RecordingService.mobileDevices().first(where: { $0.uniqueID == deviceID }) else {
            throw RecordingError.sourceUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.invalidConfiguration }
        session.addInput(input)
        guard session.canAddOutput(output) else { throw RecordingError.invalidConfiguration }
        session.addOutput(output)
        session.startRunning()
        output.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stop() async throws -> RecordingMobileDeviceResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.stopRecording()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        session.stopRunning()
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            return
        }
        let pending = continuation
        continuation = nil
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
}
