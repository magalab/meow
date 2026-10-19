import MeowRecording
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
    case microphoneUnavailable
    case cameraDenied
    case cameraUnavailable
    case insufficientDiskSpace
    case magnifierUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return L10n.recordingErrorPermissionDenied
        case .sourceUnavailable: return L10n.recordingErrorSourceUnavailable
        case .alreadyRecording: return L10n.recordingErrorAlreadyRecording
        case .invalidConfiguration: return L10n.recordingErrorInvalidConfiguration
        case let .writerFailed(message): return message
        case .microphoneDenied: return L10n.recordingErrorMicrophoneDenied
        case .microphoneUnavailable: return L10n.recordingErrorMicrophoneUnavailable
        case .cameraDenied: return L10n.recordingErrorCameraDenied
        case .cameraUnavailable: return L10n.recordingErrorCameraUnavailable
        case .insufficientDiskSpace: return L10n.recordingErrorInsufficientDiskSpace
        case .magnifierUnavailable: return L10n.recordingErrorMagnifierUnavailable
        }
    }
}

@MainActor
final class RecordingService: NSObject, ObservableObject {
    private static let capturedOverlayTitles: Set<String> = [
        CameraOverlayController.windowTitle,
    ]

    @Published private(set) var state: RecordingState = .idle {
        didSet { onStateChanged?(state, elapsed) }
    }
    @Published private(set) var elapsed: TimeInterval = 0 {
        didSet { onStateChanged?(state, elapsed) }
    }
    @Published private(set) var lastArtifact: RecordingArtifact?
    @Published private(set) var isCameraOverlayVisible = false
    @Published private(set) var isCameraOverlayChanging = false
    @Published private(set) var isMicrophoneCapturing = false
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var isMicrophoneInterrupted = false
    private(set) var canSafelyShowMagnifier = false

    var cameraOverlaySource: RecordingSource? {
        switch state {
        case .recording, .paused:
            guard let preparedSource,
                  preparedSource.kind == .display || preparedSource.kind == .region
            else { return nil }
            return preparedSource
        default:
            return nil
        }
    }

    func setCameraOverlayState(visible: Bool, changing: Bool = false) {
        isCameraOverlayVisible = visible
        isCameraOverlayChanging = changing
    }

    var onCompleted: ((RecordingArtifact) -> Void)?
    var onError: ((Error) -> Void)?
    var onStateChanged: ((RecordingState, TimeInterval) -> Void)?

    private let store: RecordingStore
    private var settings = RecordingSettings.default
    private var theme: AppTheme = .gingerCat
    private var preparedSource: RecordingSource?
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var microphoneCapture: RecordingMicrophoneCapture?
    private var microphoneCaptureID: UUID?
    private var mobileCapture: RecordingMobileDeviceCapture?
    private let mouseClickHighlighter = MouseClickHighlighterController()
    private var countdownTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0
    private var includedApplicationWindowIDs: Set<CGWindowID> = []
    private var displayFilterExceptionWindowIDs: Set<CGWindowID> = []
    private var displayFilterRefreshTask: Task<Void, Never>?
    private var isRefreshingDisplayFilter = false

    init(store: RecordingStore) {
        self.store = store
        super.init()
    }

    func apply(settings: AppSettings) {
        let previousSettings = self.settings
        self.settings = settings.recording.normalized()
        theme = settings.theme
        mouseClickHighlighter.apply(settings: settings)
        reconcileMouseClickHighlighter()
        writer?.setMouseClickHighlight(enabled: self.settings.highlightMouseClicks, color: settings.theme.recordingHighlightColor)
        if previousSettings.preventSleep != self.settings.preventSleep {
            switch state {
            case .recording, .paused:
                if self.settings.preventSleep {
                    preventSleep()
                } else {
                    allowSleep()
                }
            default:
                break
            }
        }
        reconcileDisplayFilterRefreshTask()
        if stream != nil,
           (previousSettings.excludeMeow != self.settings.excludeMeow
            || previousSettings.excludedApplicationBundleIDs != self.settings.excludedApplicationBundleIDs
            || previousSettings.excludeDesktopIcons != self.settings.excludeDesktopIcons
            || previousSettings.excludeSystemOverlays != self.settings.excludeSystemOverlays
            || previousSettings.includeMenuBar != self.settings.includeMenuBar) {
            Task { [weak self] in
                guard let self else { return }
                for _ in 0..<3 {
                    if await self.refreshDisplayFilterForNewWindows(force: true) { return }
                    try? await Task.sleep(for: .milliseconds(75))
                }
            }
        }
        store.applyRetentionPolicy(
            historyLimit: settings.recording.historyLimit,
            retentionDays: settings.recording.retentionDays,
            maxStorageMB: settings.recording.maxStorageMB
        )
    }

    func setMagnifierFrame(
        _ image: CGImage?, frame: CGRect, marker: CGPoint, zoom: Int, circular: Bool
    ) {
        writer?.setMagnifierFrame(
            image, frame: frame, marker: marker, zoom: zoom, circular: circular
        )
    }

    func setMagnifierPosition(_ frame: CGRect) {
        writer?.setMagnifierPosition(frame)
    }

    func setIncludedApplicationWindowIDs(_ windowIDs: Set<CGWindowID>) {
        includedApplicationWindowIDs = windowIDs
    }

    @discardableResult
    func refreshDisplayFilterForNewWindows(
        force: Bool = false,
        requiredWindowID: CGWindowID? = nil
    ) async -> Bool {
        switch state {
        case .recording, .paused:
            break
        default:
            return false
        }
        guard (force || !settings.excludeMeow || settings.excludeDesktopIcons),
              !isRefreshingDisplayFilter,
              let stream,
              let source = preparedSource,
              source.kind == .display || source.kind == .region
        else { return false }
        isRefreshingDisplayFilter = true
        defer { isRefreshingDisplayFilter = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard self.stream === stream else { return false }
            switch state {
            case .recording, .paused:
                break
            default:
                return false
            }
            let exceptionIDs = displayFilterExceptionIDs(in: content)
            if let requiredWindowID, !exceptionIDs.contains(requiredWindowID) { return false }
            // A caller waiting for a specific overlay needs a successful filter
            // update, even if the cached exception IDs have not changed.
            guard force || requiredWindowID != nil
                    || exceptionIDs != displayFilterExceptionWindowIDs else { return true }
            let filter = try makeFilter(for: source, content: content)
            try await stream.updateContentFilter(filter)
            displayFilterExceptionWindowIDs = exceptionIDs
            return true
        } catch {
            MeowLog.recording.error(
                "Updating recording window filter failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
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
            guard Self.microphoneDevice(for: settings.microphoneDeviceID) != nil else {
                throw RecordingError.microphoneUnavailable
            }
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
        mouseClickHighlighter.pause()
        microphoneLevel = 0
        stopElapsedTimer()
        state = .paused(elapsed: elapsed)
    }

    func resume() {
        guard case .paused = state else { return }
        writer?.setPaused(false)
        if settings.highlightMouseClicks, let preparedSource, Self.supportsCustomMouseClickHighlight(for: preparedSource.kind) {
            mouseClickHighlighter.start()
        }
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
        isMicrophoneCapturing = false
        microphoneCaptureID = nil
        microphoneLevel = 0
        isMicrophoneInterrupted = false
        canSafelyShowMagnifier = false
        isCameraOverlayChanging = false
        displayFilterRefreshTask?.cancel()
        displayFilterRefreshTask = nil
        state = .finishing
        stopElapsedTimer()
        countdownTask?.cancel()
        countdownTask = nil
        mouseClickHighlighter.onClick = nil
        mouseClickHighlighter.stop()

        if let stream {
            do {
                try await stream.stopCapture()
            } catch {
                MeowLog.recording.error(
                    "Stopping screen capture failed: \(error.localizedDescription, privacy: .public)"
                )
            }
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

    nonisolated static func microphoneDevice(for deviceID: String) -> AVCaptureDevice? {
        if deviceID.isEmpty {
            return AVCaptureDevice.default(for: .audio)
        }
        return microphones().first { $0.uniqueID == deviceID }
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
                outputURL: outputURL,
                findDevice: { id in
                    Self.mobileDevices().first { $0.uniqueID == id }
                },
                makeFailure: { failure in
                    switch failure {
                    case .unavailable: RecordingError.sourceUnavailable
                    case .invalidConfiguration: RecordingError.invalidConfiguration
                    }
                }
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
        if source.kind != .systemAudio {
            // The preview stays on screen, while RecordingWriter draws the
            // click ring into video frames independently of window filtering.
            mouseClickHighlighter.prepareForRecording()
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let currentSource: RecordingSource
        if case let .window(window) = source {
            guard let currentWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                throw RecordingError.sourceUnavailable
            }
            currentSource = .window(currentWindow)
        } else {
            currentSource = source
        }
        canSafelyShowMagnifier = (source.kind == .display || source.kind == .region)
            && content.applications.contains {
                $0.processID == ProcessInfo.processInfo.processIdentifier
            }
        let configuration = try makeConfiguration(for: currentSource)
        let filter = try makeFilter(for: currentSource, content: content)
        if source.kind == .display || source.kind == .region {
            displayFilterExceptionWindowIDs = displayFilterExceptionIDs(in: content)
        }
        store.markRecordingStarted(fileURL: outputURL, source: source.kind)
        let writer = try RecordingWriter(
            outputURL: outputURL,
            source: source.kind,
            configuration: configuration,
            captureRect: Self.captureRect(for: currentSource),
            highlightColor: theme.recordingHighlightColor,
            settings: settings,
            onStreamStopped: { [weak self] error in
                Task { @MainActor in
                    await self?.handleUnexpectedStreamStop(error)
                }
            },
            makeFailure: { failure in
                switch failure {
                case .invalidConfiguration:
                    RecordingError.invalidConfiguration
                case let .writerFailed(message):
                    RecordingError.writerFailed(message)
                }
            }
        )
        self.writer = writer
        mouseClickHighlighter.onClick = { [weak writer] point in
            writer?.recordMouseClick(at: point)
        }

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
            let captureID = UUID()
            let microphone = RecordingMicrophoneCapture(
                deviceID: settings.microphoneDeviceID,
                queue: writer.queue,
                findDevice: Self.microphoneDevice(for:),
                makeFailure: { failure in
                    switch failure {
                    case .unavailable: RecordingError.microphoneUnavailable
                    case .invalidConfiguration: RecordingError.invalidConfiguration
                    }
                }
            ) { [weak self, weak writer] sampleBuffer, level in
                writer?.appendMicrophone(sampleBuffer)
                guard let level else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.microphoneCaptureID == captureID,
                          self.isMicrophoneCapturing,
                          case .recording = self.state else { return }
                    self.microphoneLevel = level
                    self.isMicrophoneInterrupted = false
                }
            } onIssue: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.microphoneCaptureID == captureID,
                          self.isMicrophoneCapturing else { return }
                    self.microphoneLevel = 0
                    self.isMicrophoneInterrupted = true
                }
            }
            try microphone.start()
            microphoneCapture = microphone
            microphoneCaptureID = captureID
            isMicrophoneCapturing = true
        }

        try await stream.startCapture()
        if settings.highlightMouseClicks, Self.supportsCustomMouseClickHighlight(for: source.kind) {
            mouseClickHighlighter.start()
        }
        if settings.preventSleep {
            preventSleep()
        }
        state = .recording(startedAt: Date())
        elapsed = 0
        startElapsedTimer()
        reconcileDisplayFilterRefreshTask()
    }

    private func reconcileDisplayFilterRefreshTask() {
        let shouldRefresh: Bool
        switch state {
        case .recording, .paused:
            shouldRefresh = (preparedSource?.kind == .display || preparedSource?.kind == .region)
                && (!settings.excludeMeow || settings.excludeDesktopIcons)
        default:
            shouldRefresh = false
        }
        if shouldRefresh {
            guard displayFilterRefreshTask == nil else { return }
            displayFilterRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await self?.refreshDisplayFilterForNewWindows()
                }
            }
        } else {
            displayFilterRefreshTask?.cancel()
            displayFilterRefreshTask = nil
        }
    }

    private func makeFilter(
        for source: RecordingSource,
        content: SCShareableContent
    ) throws -> SCContentFilter {
        switch source {
        case let .display(display), let .region(display, _, _), let .systemAudio(display):
            var excludedBundleIDs = Set(settings.excludedApplicationBundleIDs.map { $0.lowercased() })
            let systemOverlayBundleIDs: Set<String> = [
                "com.apple.controlcenter",
                "com.apple.notificationcenterui",
                "com.apple.dock",
                "com.apple.systemuiserver",
            ]
            if settings.excludeSystemOverlays {
                excludedBundleIDs.formUnion(systemOverlayBundleIDs)
            }
            if settings.excludeDesktopIcons {
                excludedBundleIDs.insert("com.apple.finder")
            }

            // Excluding our process keeps windows created after the stream starts,
            // including the magnifier, out of the recording. Explicit exceptions
            // preserve overlays intentionally meant to appear in the movie.
            let ownProcessID = ProcessInfo.processInfo.processIdentifier
            if !content.applications.contains(where: { $0.processID == ownProcessID }) {
                // ScreenCaptureKit can omit this process from its application
                // list. Exclude the already visible border by window ID, and
                // keep the magnifier disabled for this stream.
                let excludedWindows = content.windows.filter { window in
                    if window.title == ScreenMagnifierController.windowTitle
                        || window.title == RecordingRegionBorderController.windowTitle {
                        return true
                    }
                    if let clickWindowID = mouseClickHighlighter.windowID,
                       window.windowID == clickWindowID { return true }
                    if includedApplicationWindowIDs.contains(window.windowID) { return false }
                    if Self.capturedOverlayTitles.contains(window.title ?? "") { return false }
                    guard let application = window.owningApplication else { return false }
                    if application.processID == ownProcessID { return settings.excludeMeow }
                    let bundleID = application.bundleIdentifier.lowercased()
                    if settings.excludeDesktopIcons && bundleID == "com.apple.finder" {
                        return window.title?.isEmpty ?? true
                    }
                    return excludedBundleIDs.contains(bundleID)
                }
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                filter.includeMenuBar = settings.includeMenuBar
                return filter
            }
            let excludedApplications = content.applications.filter { application in
                application.processID == ownProcessID
                    || excludedBundleIDs.contains(application.bundleIdentifier.lowercased())
            }
            let exceptingWindows = content.windows.filter { window in
                shouldExceptWindow(
                    window,
                    ownProcessID: ownProcessID,
                    capturedOverlayTitles: Self.capturedOverlayTitles
                )
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: exceptingWindows
            )
            filter.includeMenuBar = settings.includeMenuBar
            return filter
        case let .window(window):
            return SCContentFilter(desktopIndependentWindow: window)
        case let .application(application, display):
            let clickWindows = application.processID == ProcessInfo.processInfo.processIdentifier
                ? content.windows.filter { $0.windowID == mouseClickHighlighter.windowID }
                : []
            return SCContentFilter(
                display: display,
                including: [application],
                exceptingWindows: clickWindows
            )
        case let .contentFilter(filter):
            return filter
        case .mobileDevice:
            throw RecordingError.sourceUnavailable
        }
    }

    private func displayFilterExceptionIDs(in content: SCShareableContent) -> Set<CGWindowID> {
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return Set(content.windows.compactMap { window in
            shouldExceptWindow(
                window,
                ownProcessID: ownProcessID,
                capturedOverlayTitles: Self.capturedOverlayTitles
            ) ? window.windowID : nil
        })
    }

    private func shouldExceptWindow(
        _ window: SCWindow,
        ownProcessID: pid_t,
        capturedOverlayTitles: Set<String>
    ) -> Bool {
        if window.title == ScreenMagnifierController.windowTitle
            || window.title == RecordingRegionBorderController.windowTitle {
            return false
        }
        if let clickWindowID = mouseClickHighlighter.windowID,
           window.windowID == clickWindowID { return false }
        if includedApplicationWindowIDs.contains(window.windowID) {
            return true
        }
        guard let application = window.owningApplication else { return false }
        if application.processID == ownProcessID {
            return capturedOverlayTitles.contains(window.title ?? "") || !settings.excludeMeow
        }
        return settings.excludeDesktopIcons
            && application.bundleIdentifier.lowercased() == "com.apple.finder"
            && !(window.title?.isEmpty ?? true)
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
        configuration.showMouseClicks = false
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

    private static func captureRect(for source: RecordingSource) -> CGRect? {
        switch source {
        case let .display(display), let .application(_, display):
            return ScreenCaptureService.screen(for: display.displayID)?.frame
                ?? ScreenCaptureService.appKitRect(fromCoreGraphics: display.frame)
        case let .region(display, rect, _):
            let frame = ScreenCaptureService.screen(for: display.displayID)?.frame
                ?? ScreenCaptureService.appKitRect(fromCoreGraphics: display.frame)
            return rect.offsetBy(dx: frame.minX, dy: frame.minY)
        case let .window(window):
            return ScreenCaptureService.appKitRect(fromCoreGraphics: window.frame)
        case let .contentFilter(filter):
            return ScreenCaptureService.appKitRect(fromCoreGraphics: filter.contentRect)
        case .systemAudio, .mobileDevice:
            return nil
        }
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
        isMicrophoneCapturing = false
        microphoneCaptureID = nil
        microphoneLevel = 0
        isMicrophoneInterrupted = false
        MeowLog.recording.error(
            "Recording failed: \(error.localizedDescription, privacy: .public)"
        )
        mouseClickHighlighter.onClick = nil
        canSafelyShowMagnifier = false
        setCameraOverlayState(visible: false)
        displayFilterRefreshTask?.cancel()
        displayFilterRefreshTask = nil
        displayFilterExceptionWindowIDs = []
        stopElapsedTimer()
        countdownTask?.cancel()
        countdownTask = nil
        let stream = self.stream
        self.stream = nil
        if let stream {
            Task {
                do {
                    try await stream.stopCapture()
                } catch {
                    MeowLog.recording.error(
                        "Stopping failed screen capture failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        microphoneCapture?.stop()
        microphoneCapture = nil
        mouseClickHighlighter.stop()
        mobileCapture = nil
        writer = nil
        allowSleep()
        state = .failed(error.localizedDescription)
        preparedSource = nil
        onError?(error)
    }

    private func reset() {
        isMicrophoneCapturing = false
        microphoneCaptureID = nil
        microphoneLevel = 0
        isMicrophoneInterrupted = false
        mouseClickHighlighter.onClick = nil
        canSafelyShowMagnifier = false
        setCameraOverlayState(visible: false)
        displayFilterRefreshTask?.cancel()
        displayFilterRefreshTask = nil
        displayFilterExceptionWindowIDs = []
        mouseClickHighlighter.stop()
        state = .idle
        preparedSource = nil
        elapsed = 0
    }

    private func reconcileMouseClickHighlighter() {
        guard let preparedSource,
              Self.supportsCustomMouseClickHighlight(for: preparedSource.kind)
        else {
            mouseClickHighlighter.stop()
            return
        }
        if case .recording = state, settings.highlightMouseClicks {
            mouseClickHighlighter.start()
        } else {
            mouseClickHighlighter.pause()
        }
    }

    private static func supportsCustomMouseClickHighlight(for source: RecordingSourceKind) -> Bool {
        switch source {
        case .display, .region, .application, .window:
            return true
        case .systemAudio, .mobileDevice:
            return false
        }
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

private extension AppTheme {
    var recordingHighlightColor: RecordingHighlightColor {
        switch self {
        case .gingerCat: return RecordingHighlightColor(red: 0.85, green: 0.47, blue: 0.24)
        case .mistBlue: return RecordingHighlightColor(red: 0.23, green: 0.31, blue: 0.54)
        case .graphiteAmber: return RecordingHighlightColor(red: 0.77, green: 0.54, blue: 0.23)
        case .mossInk: return RecordingHighlightColor(red: 0.29, green: 0.42, blue: 0.34)
        }
    }
}
