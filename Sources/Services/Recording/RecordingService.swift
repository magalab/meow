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
                queue: writer.queue
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
    private var hasLoggedAppendFailure = false
    private var hasLoggedMagnifierSnapshot = false
    private var hasLoggedMagnifierOutput = false
    private let ciContext = CIContext()
    private let mouseClickCompositor: RecordingMouseClickCompositor
    private let magnifierCompositor: RecordingMagnifierCompositor
    private var latestFrameStorage: CVPixelBuffer?

    var duration: TimeInterval {
        queue.sync {
            self.durationOnQueue
        }
    }

    var latestFrame: CGImage? {
        queue.sync {
            guard let pixelBuffer = latestFrameStorage else { return nil }
            return ciContext.createCGImage(
                CIImage(cvPixelBuffer: pixelBuffer),
                from: CGRect(
                    x: 0,
                    y: 0,
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )
        }
    }

    init(
        outputURL: URL,
        source: RecordingSourceKind,
        configuration: SCStreamConfiguration,
        captureRect: CGRect?,
        highlightColor: RecordingHighlightColor,
        settings: RecordingSettings,
        onStreamStopped: @escaping @Sendable (Error) -> Void
    ) throws {
        self.outputURL = outputURL
        self.source = source
        self.settings = settings
        self.onStreamStopped = onStreamStopped
        mouseClickCompositor = RecordingMouseClickCompositor(
            captureRect: captureRect,
            enabled: settings.highlightMouseClicks,
            color: highlightColor
        )
        magnifierCompositor = RecordingMagnifierCompositor(captureRect: captureRect)
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

    func setMouseClickHighlight(enabled: Bool, color: RecordingHighlightColor) {
        queue.async {
            self.mouseClickCompositor.apply(enabled: enabled, color: color)
        }
    }

    func recordMouseClick(at point: CGPoint) {
        queue.async {
            self.mouseClickCompositor.recordClick(at: point)
        }
    }

    func setMagnifierFrame(
        _ image: CGImage?, frame: CGRect, marker: CGPoint, zoom: Int, circular: Bool
    ) {
        queue.async {
            self.magnifierCompositor.setSnapshot(
                image, frame: frame, marker: marker, zoom: zoom, circular: circular
            )
            if image != nil && !self.hasLoggedMagnifierSnapshot {
                self.hasLoggedMagnifierSnapshot = true
                MeowLog.recording.notice(
                    "Magnifier snapshot received by writer; renderSucceeded=\(self.magnifierCompositor.isActive, privacy: .public), frame=\(String(describing: frame), privacy: .public)"
                )
            }
        }
    }

    func setMagnifierPosition(_ frame: CGRect) {
        queue.async {
            self.magnifierCompositor.setFrame(frame)
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
            do {
                finalURL = try await RecordingAudioMixer.mixTracks(in: outputURL)
            } catch is RecordingAudioMixerError {
                throw RecordingError.invalidConfiguration
            }
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
            latestFrameStorage = sampleBuffer.imageBuffer
            let clickedSample = mouseClickCompositor.composite(sampleBuffer)
            let renderedSample = magnifierCompositor.composite(clickedSample)
            if magnifierCompositor.isActive && !hasLoggedMagnifierOutput {
                hasLoggedMagnifierOutput = true
                let pixelFormat = sampleBuffer.imageBuffer.map(CVPixelBufferGetPixelFormatType) ?? 0
                MeowLog.recording.notice(
                    "Magnifier video composition; applied=\(renderedSample !== clickedSample, privacy: .public), pixelFormat=\(pixelFormat, privacy: .public), overlayFrame=\(String(describing: self.magnifierCompositor.overlayFrame), privacy: .public), captureRect=\(String(describing: self.magnifierCompositor.captureRect), privacy: .public), failure=\(self.magnifierCompositor.lastFailureReason ?? "none", privacy: .public)"
                )
            }
            append(
                renderedSample,
                to: videoInput,
                source: .video,
                establishesSession: true
            )
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
        } else if !hasLoggedAppendFailure {
            hasLoggedAppendFailure = true
            MeowLog.recording.error(
                "Recording writer rejected a \(String(describing: source), privacy: .public) sample: \(self.assetWriter.error?.localizedDescription ?? "unknown error", privacy: .public)"
            )
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

private final class RecordingMicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let deviceID: String
    private let queue: DispatchQueue
    private let handler: (CMSampleBuffer, Float?) -> Void
    private let onIssue: @Sendable () -> Void
    private let session = AVCaptureSession()
    private var lastLevelUpdate = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    init(
        deviceID: String,
        queue: DispatchQueue,
        handler: @escaping (CMSampleBuffer, Float?) -> Void,
        onIssue: @escaping @Sendable () -> Void
    ) {
        self.deviceID = deviceID
        self.queue = queue
        self.handler = handler
        self.onIssue = onIssue
    }

    func start() throws {
        guard let device = RecordingService.microphoneDevice(for: deviceID) else {
            throw RecordingError.microphoneUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.invalidConfiguration }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw RecordingError.invalidConfiguration }
        session.addOutput(output)
        session.startRunning()
        guard session.isRunning else { throw RecordingError.microphoneUnavailable }
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
            ) { [onIssue] notification in
                if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error {
                    MeowLog.recording.error(
                        "Microphone capture interrupted: \(error.localizedDescription, privacy: .public)"
                    )
                }
                onIssue()
            },
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if session.isRunning {
            session.stopRunning()
        }
    }

    func captureOutput(
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
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RecordingMobileDeviceResult, Error>?
    private var stopTimeoutTask: Task<Void, Never>?

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
            lock.withLock {
                self.continuation = continuation
            }
            stopTimeoutTask?.cancel()
            stopTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.resumeStop(throwing: RecordingError.sourceUnavailable)
            }
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
