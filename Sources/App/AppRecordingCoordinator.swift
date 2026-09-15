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
    private let windowCoordinator: AppWindowCoordinator
    private let actions: Actions

    private var recordingTask: Task<Void, Never>?
    private var allowsVisualOverlays = false

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
    }

    func cancel() {
        recordingTask?.cancel()
    }

    func resetVisualOverlays() {
        allowsVisualOverlays = false
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
        Task { await screenMagnifierController.toggle() }
    }

    func saveCurrentFrame() {
        Task { @MainActor in
            do {
                _ = try await recordingService.saveCurrentFrame()
            } catch {
                NSLog("[Meow] Failed to save recording frame: %@", String(describing: error))
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
                    }
                )
            )
        )
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
        guard settings.cameraOverlayEnabled,
              source.kind == .display || source.kind == .region
        else {
            cameraOverlayController.stop()
            return
        }

        let display: SCDisplay?
        switch source {
        case let .display(value), let .region(value, _, _), let .systemAudio(value):
            display = value
        case let .application(_, value):
            display = value
        case .contentFilter, .window, .mobileDevice:
            display = nil
        }
        try await cameraOverlayController.start(
            deviceID: settings.cameraDeviceID,
            shape: settings.cameraOverlayShape,
            on: display.flatMap { ScreenCaptureService.screen(for: $0.displayID) }
                ?? actions.activeScreen()
        )
    }
}
