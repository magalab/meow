import AppKit

@MainActor
final class AppLifecycleCoordinator {
    struct Actions {
        let systemDidWake: @MainActor () -> Void
        let systemWillSleep: @MainActor () -> Void
        let retryPermissions: @MainActor () -> Void
        let refreshSpeechPermission: @MainActor () -> Void

        let shutdownWhiteboard: @MainActor () -> Void
        let unregisterHotkeys: @MainActor () -> Void
        let cancelUpload: @MainActor () -> Void
        let captureCoordinatorLoaded: @MainActor () -> Bool
        let cancelCapture: @MainActor () -> Void
        let recordingServiceLoaded: @MainActor () -> Bool
        let cancelRecording: @MainActor () -> Void
        let recordingServiceIsActive: @MainActor () -> Bool
        let stopRecording: @MainActor () async -> Void
        let stopCameraOverlay: @MainActor () -> Void
        let stopMagnifier: @MainActor () -> Void
        let cancelCaptureOverlay: @MainActor () -> Void
        let cancelCaptureEditor: @MainActor () -> Void
        let closePostCaptureActions: @MainActor () -> Void
        let closePinnedImages: @MainActor () -> Void
        let speechRecognitionServiceLoaded: @MainActor () -> Bool
        let cancelSpeechRecognition: @MainActor () -> Void
        let speechSynthesisServiceLoaded: @MainActor () -> Bool
        let cancelSpeechSynthesis: @MainActor () -> Void
        let hideSpeechOverlay: @MainActor () -> Void
        let stopKeystrokeVisualizer: @MainActor () -> Void
        let systemMonitorServiceLoaded: @MainActor () -> Bool
        let stopSystemMonitor: @MainActor () -> Void
        let stopHealthReminder: @MainActor () -> Void
        let stopKeepAwake: @MainActor () async -> Void
        let stopClipboardMonitoring: @MainActor () -> Void
        let stopDockIcon: @MainActor () -> Void
        let removeEventMonitors: @MainActor () -> Void
        let shutdownUploads: @MainActor () async -> Void
    }

    private let actions: Actions
    private var workspaceWakeObserver: NSObjectProtocol?
    private var workspaceSleepObserver: NSObjectProtocol?
    private var terminationShutdownStarted = false

    init(actions: Actions) {
        self.actions = actions
    }

    func observeSystemPowerState() {
        guard workspaceWakeObserver == nil, workspaceSleepObserver == nil else { return }

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.actions.systemDidWake()
            }
        }
        workspaceSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.actions.systemWillSleep()
            }
        }
    }

    func applicationDidBecomeActive() {
        actions.retryPermissions()
        actions.refreshSpeechPermission()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationShutdownStarted else { return .terminateNow }
        terminationShutdownStarted = true
        Task { @MainActor [weak self, weak sender] in
            await self?.actions.stopKeepAwake()
            await self?.actions.shutdownUploads()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate() {
        actions.shutdownWhiteboard()
        actions.unregisterHotkeys()
        actions.cancelUpload()
        if actions.captureCoordinatorLoaded() {
            actions.cancelCapture()
        }
        if actions.recordingServiceLoaded() {
            actions.cancelRecording()
        }
        if actions.recordingServiceLoaded(), actions.recordingServiceIsActive() {
            Task { @MainActor in
                await actions.stopRecording()
            }
        }
        actions.stopCameraOverlay()
        actions.stopMagnifier()
        actions.cancelCaptureOverlay()
        actions.cancelCaptureEditor()
        actions.closePostCaptureActions()
        actions.closePinnedImages()
        #if MEOW_VOICE
        if actions.speechRecognitionServiceLoaded() {
            actions.cancelSpeechRecognition()
        }
        if actions.speechSynthesisServiceLoaded() {
            actions.cancelSpeechSynthesis()
        }
        actions.hideSpeechOverlay()
        #endif
        actions.stopKeystrokeVisualizer()
        if actions.systemMonitorServiceLoaded() {
            actions.stopSystemMonitor()
        }
        actions.stopHealthReminder()
        Task { @MainActor in
            await actions.stopKeepAwake()
        }
        actions.stopClipboardMonitoring()
        actions.stopDockIcon()
        removeSystemPowerObservers()
        actions.removeEventMonitors()
    }

    private func removeSystemPowerObservers() {
        if let workspaceWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
            self.workspaceWakeObserver = nil
        }
        if let workspaceSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceSleepObserver)
            self.workspaceSleepObserver = nil
        }
    }
}
