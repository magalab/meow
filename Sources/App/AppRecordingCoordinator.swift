import AppKit
import AVFoundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppRecordingCoordinator {
    struct Actions {
        let settings: @MainActor () -> AppSettings
        let captureIsBusy: @MainActor () -> Bool
        let hideTransientPanels: @MainActor () -> Void
        let prepareWhiteboard: @MainActor () -> Set<CGWindowID>
        let restoreWhiteboard: @MainActor () -> Void
        let activeScreen: @MainActor () -> NSScreen?
        let setSystemAudioMode: @MainActor () -> Void
        let presentError: @MainActor (Error) -> Void
    }

    private let screenCaptureService: ScreenCaptureService
    private let captureOverlayController: CaptureOverlayController
    private let recordingContentPickerController: RecordingContentPickerController
    private let recordingService: RecordingService
    private let recordingStore: RecordingStore
    private let cameraOverlayController: CameraOverlayController
    private let screenMagnifierController: ScreenMagnifierController
    private let regionBorderController = RecordingRegionBorderController()
    private let windowCoordinator: AppWindowCoordinator
    private let actions: Actions

    private var recordingTask: Task<Void, Never>?
    private var allowsVisualOverlays = false
    private var lastCameraPreferenceEnabled: Bool
    private var lastCameraDeviceID: String
    private var lastCameraShape: RecordingCameraOverlayShape
    private var cameraChangeTask: Task<Void, Never>?
    private var cameraChangeGeneration: UInt64 = 0

    var isBusy: Bool {
        recordingTask != nil
    }

    init(
        screenCaptureService: ScreenCaptureService,
        captureOverlayController: CaptureOverlayController,
        recordingContentPickerController: RecordingContentPickerController,
        recordingService: RecordingService,
        recordingStore: RecordingStore,
        cameraOverlayController: CameraOverlayController,
        screenMagnifierController: ScreenMagnifierController,
        windowCoordinator: AppWindowCoordinator,
        actions: Actions
    ) {
        self.screenCaptureService = screenCaptureService
        self.captureOverlayController = captureOverlayController
        self.recordingContentPickerController = recordingContentPickerController
        self.recordingService = recordingService
        self.recordingStore = recordingStore
        self.cameraOverlayController = cameraOverlayController
        self.screenMagnifierController = screenMagnifierController
        self.windowCoordinator = windowCoordinator
        self.actions = actions
        lastCameraPreferenceEnabled = actions.settings().recording.cameraOverlayEnabled
        lastCameraDeviceID = actions.settings().recording.cameraDeviceID
        lastCameraShape = actions.settings().recording.cameraOverlayShape
        screenMagnifierController.onError = actions.presentError
        screenMagnifierController.onFrame = { [weak recordingService] image, frame, marker, zoom, circular in
            recordingService?.setMagnifierFrame(
                image, frame: frame, marker: marker, zoom: zoom, circular: circular
            )
        }
        screenMagnifierController.onPosition = { [weak recordingService] frame in
            recordingService?.setMagnifierPosition(frame)
        }
    }

    func cancel() {
        recordingTask?.cancel()
        regionBorderController.stop()
    }

    func resetVisualOverlays() {
        allowsVisualOverlays = false
        cameraChangeGeneration &+= 1
        cameraChangeTask?.cancel()
        cameraChangeTask = nil
        recordingService.setCameraOverlayState(visible: false)
        regionBorderController.stop()
    }

    func cameraOverlaySettingsDidChange(_ settings: RecordingSettings) {
        let enabled = settings.cameraOverlayEnabled
        let enabledChanged = enabled != lastCameraPreferenceEnabled
        let deviceChanged = settings.cameraDeviceID != lastCameraDeviceID
        let shapeChanged = settings.cameraOverlayShape != lastCameraShape
        guard recordingService.cameraOverlaySource != nil else { return }
        lastCameraPreferenceEnabled = enabled
        lastCameraDeviceID = settings.cameraDeviceID
        lastCameraShape = settings.cameraOverlayShape
        if enabledChanged {
            setCameraOverlayEnabled(enabled)
        } else if deviceChanged || (shapeChanged && recordingService.isCameraOverlayChanging) {
            guard recordingService.isCameraOverlayVisible || recordingService.isCameraOverlayChanging else { return }
            setCameraOverlayEnabled(true, restart: true)
        } else if shapeChanged, recordingService.isCameraOverlayVisible {
            cameraOverlayController.apply(shape: settings.cameraOverlayShape)
        }
    }

    func magnifierSettingsDidChange(_ settings: RecordingSettings) {
        screenMagnifierController.apply(settings: settings)
    }

    func toggleCameraOverlay() {
        guard recordingService.cameraOverlaySource != nil else { return }
        setCameraOverlayEnabled(!recordingService.isCameraOverlayVisible)
    }

    private func setCameraOverlayEnabled(_ enabled: Bool, restart: Bool = false) {
        if enabled, recordingService.isCameraOverlayVisible,
           !recordingService.isCameraOverlayChanging, !restart { return }
        cameraChangeGeneration &+= 1
        let generation = cameraChangeGeneration
        cameraChangeTask?.cancel()
        cameraChangeTask = nil
        guard enabled, let source = recordingService.cameraOverlaySource else {
            cameraOverlayController.stop()
            recordingService.setCameraOverlayState(visible: false)
            MeowLog.recording.notice("Camera overlay disabled during recording")
            Task { await recordingService.refreshDisplayFilterForNewWindows(force: true) }
            return
        }
        recordingService.setCameraOverlayState(visible: false, changing: true)
        let settings = actions.settings().recording
        cameraChangeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let screen = Self.cameraScreen(for: source) ?? actions.activeScreen()
                try await cameraOverlayController.start(
                    deviceID: settings.cameraDeviceID,
                    shape: settings.cameraOverlayShape,
                    on: screen,
                    within: Self.cameraRecordingFrame(for: source, on: screen)
                )
                guard generation == cameraChangeGeneration,
                      recordingService.cameraOverlaySource != nil,
                      let windowID = cameraOverlayController.windowID
                else { return }
                var included = false
                for _ in 0..<8 {
                    included = await recordingService.refreshDisplayFilterForNewWindows(
                        force: true,
                        requiredWindowID: windowID
                    )
                    if included { break }
                    try await Task.sleep(for: .milliseconds(75))
                }
                guard included else { throw RecordingError.cameraUnavailable }
                guard generation == cameraChangeGeneration,
                      recordingService.cameraOverlaySource != nil
                else { return }
                recordingService.setCameraOverlayState(visible: true)
                MeowLog.recording.notice(
                    "Camera overlay enabled during recording; windowID=\(windowID, privacy: .public)"
                )
            } catch {
                guard generation == cameraChangeGeneration else { return }
                cameraOverlayController.stop()
                recordingService.setCameraOverlayState(visible: false)
                await recordingService.refreshDisplayFilterForNewWindows(force: true)
                if !(error is CancellationError) { actions.presentError(error) }
            }
        }
    }

    func stopRegionBorder() {
        regionBorderController.stop()
    }

    func pauseOrResume() {
        recordingService.pauseOrResume()
    }

    func stop() {
        Task { await recordingService.stop() }
    }

    func toggleMagnifier() {
        guard recordingService.state.isActive, allowsVisualOverlays else {
            screenMagnifierController.stop()
            return
        }
        guard recordingService.canSafelyShowMagnifier else {
            actions.presentError(RecordingError.magnifierUnavailable)
            return
        }
        screenMagnifierController.apply(settings: actions.settings().recording)
        Task {
            do {
                try await screenMagnifierController.toggle()
            } catch {
                actions.presentError(error)
            }
        }
    }

    func saveCurrentFrame() {
        Task { @MainActor in
            do {
                _ = try await recordingService.saveCurrentFrame()
            } catch {
                MeowLog.recording.error(
                    "Failed to save recording frame: \(error.localizedDescription, privacy: .private(mask: .hash))"
                )
                actions.presentError(error)
            }
        }
    }

    func showRecordingControlIfNeeded() {
        if actions.settings().recording.showFloatingControls {
            showRecordingControl()
        } else {
            hideRecordingControl()
        }
    }

    var recordingStateShowsControls: Bool {
        guard recordingService.state.isActive else { return false }
        switch recordingService.state {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    func showRecordingControl() {
        windowCoordinator.showRecordingControl(
            contentView: NSHostingView(
                rootView: RecordingControlView(
                    service: recordingService,
                    onStop: { [weak self] in
                        self?.stop()
                    },
                    onSaveFrame: { [weak self] in
                        self?.saveCurrentFrame()
                    },
                    onToggleMagnifier: { [weak self] in
                        self?.toggleMagnifier()
                    },
                    onToggleCamera: { [weak self] in
                        self?.toggleCameraOverlay()
                    }
                )
            )
        )
        Task { await recordingService.refreshDisplayFilterForNewWindows() }
    }

    func hideRecordingControl() {
        windowCoordinator.hideRecordingControl()
    }

    func showRecordingPreview(_ artifact: RecordingArtifact) {
        windowCoordinator.showRecordingPreview(size: recordingPreviewPanelSize(for: artifact)) {
            NSHostingController(
                rootView: RecordingPreviewView(
                    artifact: artifact,
                    onTrim: { [weak self] in
                        self?.windowCoordinator.hideRecordingPreview()
                        self?.showRecordingTrimmer(for: artifact.fileURL)
                    },
                    onClose: { [weak self] in
                        self?.windowCoordinator.hideRecordingPreview()
                    }
                )
            )
        }
    }

    func showRecordingHistory() {
        windowCoordinator.showRecordingHistory(
            contentViewController: NSHostingController(
                rootView: RecordingHistoryView(
                    store: recordingStore,
                    theme: actions.settings().theme,
                    onDelete: { [weak self] artifact in
                        self?.recordingStore.delete(artifact)
                    },
                    onTrim: { [weak self] artifact in
                        self?.showRecordingTrimmer(for: artifact.fileURL)
                    }
                )
            ),
            title: L10n.recordingHistoryTitle
        )
    }

    func showRecordingTrimmer(for url: URL) {
        windowCoordinator.showRecordingTrimmer(
            for: url,
            contentViewController: NSHostingController(
                rootView: RecordingTrimmerView(sourceURL: url)
            )
        )
    }

    private func recordingPreviewPanelSize(for artifact: RecordingArtifact) -> NSSize {
        guard artifact.width > 0, artifact.height > 0 else {
            return NSSize(width: 560, height: 260)
        }
        let aspectRatio = CGFloat(artifact.height) / CGFloat(artifact.width)
        let width: CGFloat = 640
        let previewHeight = min(420, max(220, width * aspectRatio))
        return NSSize(width: width, height: previewHeight + 104)
    }

    func triggerRecording(mode: ScreenshotCaptureMode) {
        guard canStartRecording else { return }
        actions.hideTransientPanels()

        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }
            do {
                let whiteboardWindowIDs = mode.includesApplicationOverlays
                    ? actions.prepareWhiteboard()
                    : []
                let session = try await screenCaptureService.prepareSession(
                    includingApplicationWindowIDs: whiteboardWindowIDs
                )
                guard let selection = await captureOverlayController.present(session: session, mode: mode) else {
                    actions.restoreWhiteboard()
                    return
                }
                let source: RecordingSource
                switch selection {
                case let .display(display, _):
                    source = .display(display)
                case let .region(display, rect, scale):
                    source = .region(display: display, rectInDisplayPoints: rect, scale: scale)
                case let .window(window, _):
                    source = .window(window)
                }
                allowsVisualOverlays = source.kind == .display || source.kind == .region
                try await prepareCameraOverlayIfNeeded(for: source)
                try Task.checkCancellation()
                if case let .region(display, rect, _) = source,
                   session.content.applications.contains(where: {
                       $0.processID == ProcessInfo.processInfo.processIdentifier
                   }),
                   let screen = ScreenCaptureService.screen(for: display.displayID) {
                    regionBorderController.show(rect, on: screen)
                }
                await recordingService.start(source: source)
                if recordingService.state.isActive {
                    cameraOverlaySettingsDidChange(actions.settings().recording)
                    let cameraEnabled = actions.settings().recording.cameraOverlayEnabled
                    if !recordingService.isCameraOverlayChanging,
                       cameraEnabled != recordingService.isCameraOverlayVisible {
                        setCameraOverlayEnabled(cameraEnabled)
                    }
                    showRecordingControlIfNeeded()
                } else {
                    regionBorderController.stop()
                    actions.restoreWhiteboard()
                }
            } catch {
                cameraOverlayController.stop()
                recordingService.setCameraOverlayState(visible: false)
                regionBorderController.stop()
                actions.restoreWhiteboard()
                actions.presentError(error)
            }
        }
    }

    func triggerApplicationRecording() {
        guard canStartRecording else { return }
        actions.hideTransientPanels()

        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }
            do {
                let session = try await screenCaptureService.prepareSession()
                let applications = applicationCandidates(from: session)
                guard let application = chooseApplication(from: applications),
                      let display = displayAtPointer(in: session)
                else {
                    actions.restoreWhiteboard()
                    return
                }
                let source = RecordingSource.application(application, display: display)
                allowsVisualOverlays = false
                try await prepareCameraOverlayIfNeeded(for: source)
                await recordingService.start(source: source)
                if recordingService.state.isActive {
                    showRecordingControlIfNeeded()
                } else {
                    actions.restoreWhiteboard()
                }
            } catch {
                actions.restoreWhiteboard()
                actions.presentError(error)
            }
        }
    }

    func triggerMultipleWindowRecording() {
        guard canStartRecording else { return }
        actions.hideTransientPanels()
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }
            guard let filter = await recordingContentPickerController.selectMultipleWindows() else {
                return
            }
            allowsVisualOverlays = false
            await recordingService.start(source: .contentFilter(filter))
            if recordingService.state.isActive {
                showRecordingControlIfNeeded()
            } else {
                actions.restoreWhiteboard()
            }
        }
    }

    func triggerSystemAudioRecording() {
        guard canStartRecording else { return }
        if !actions.settings().recording.audioMode.capturesSystemAudio {
            actions.setSystemAudioMode()
        }
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }
            do {
                let session = try await screenCaptureService.prepareSession()
                guard let display = displayAtPointer(in: session) else {
                    throw RecordingError.sourceUnavailable
                }
                await recordingService.start(source: .systemAudio(display))
                if recordingService.state.isActive {
                    showRecordingControlIfNeeded()
                } else {
                    actions.restoreWhiteboard()
                }
            } catch {
                actions.restoreWhiteboard()
                actions.presentError(error)
            }
        }
    }

    func triggerMobileDeviceRecording() {
        guard canStartRecording else { return }
        let devices = RecordingService.mobileDevices()
        guard let device = chooseMobileDevice(from: devices) else { return }
        actions.hideTransientPanels()
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }
            await recordingService.start(source: .mobileDevice(device.uniqueID))
            if recordingService.state.isActive {
                showRecordingControlIfNeeded()
            }
        }
    }

    private var canStartRecording: Bool {
        recordingTask == nil && !actions.captureIsBusy() && recordingService.state.isActive == false
    }

    private func applicationCandidates(from session: CaptureSession) -> [SCRunningApplication] {
        var seen = Set<String>()
        return session.windows
            .compactMap(\.owningApplication)
            .filter { application in
                guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
                return seen.insert(application.bundleIdentifier).inserted
            }
            .sorted {
                $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
            }
    }

    private func chooseApplication(
        from applications: [SCRunningApplication]
    ) -> SCRunningApplication? {
        guard !applications.isEmpty else {
            actions.presentError(RecordingError.sourceUnavailable)
            return nil
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        for application in applications {
            picker.addItem(withTitle: application.applicationName)
        }
        let alert = NSAlert()
        alert.messageText = L10n.recordingChooseApplicationTitle
        alert.informativeText = L10n.recordingChooseApplicationSubtitle
        alert.accessoryView = picker
        alert.addButton(withTitle: L10n.recordingStart)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selectedIndex = picker.indexOfSelectedItem
        guard applications.indices.contains(selectedIndex) else { return nil }
        return applications[selectedIndex]
    }

    private func chooseMobileDevice(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        guard !devices.isEmpty else {
            actions.presentError(RecordingError.sourceUnavailable)
            return nil
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        for device in devices {
            picker.addItem(withTitle: device.localizedName)
        }
        let alert = NSAlert()
        alert.messageText = L10n.recordingChooseMobileTitle
        alert.informativeText = L10n.recordingChooseMobileSubtitle
        alert.accessoryView = picker
        alert.addButton(withTitle: L10n.recordingStart)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selectedIndex = picker.indexOfSelectedItem
        guard devices.indices.contains(selectedIndex) else { return nil }
        return devices[selectedIndex]
    }

    private func displayAtPointer(in session: CaptureSession) -> SCDisplay? {
        let point = NSEvent.mouseLocation
        return session.displays.first { $0.screen.frame.contains(point) }?.display
            ?? session.displays.first?.display
    }

    private func prepareCameraOverlayIfNeeded(for source: RecordingSource) async throws {
        let settings = actions.settings().recording
        lastCameraPreferenceEnabled = settings.cameraOverlayEnabled
        lastCameraDeviceID = settings.cameraDeviceID
        lastCameraShape = settings.cameraOverlayShape
        guard settings.cameraOverlayEnabled,
              source.kind == .display || source.kind == .region
        else {
            cameraOverlayController.stop()
            recordingService.setCameraOverlayState(visible: false)
            return
        }

        let screen = Self.cameraScreen(for: source) ?? actions.activeScreen()
        try await cameraOverlayController.start(
            deviceID: settings.cameraDeviceID,
            shape: settings.cameraOverlayShape,
            on: screen,
            within: Self.cameraRecordingFrame(for: source, on: screen)
        )
        recordingService.setCameraOverlayState(visible: true)
    }

    private static func cameraScreen(for source: RecordingSource) -> NSScreen? {
        switch source {
        case let .display(display), let .region(display, _, _), let .systemAudio(display),
             let .application(_, display):
            return ScreenCaptureService.screen(for: display.displayID)
        case .contentFilter, .window, .mobileDevice:
            return nil
        }
    }

    private static func cameraRecordingFrame(for source: RecordingSource, on screen: NSScreen?) -> CGRect? {
        guard case let .region(_, rect, _) = source, let screen else { return nil }
        return rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }
}
