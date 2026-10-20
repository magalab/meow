import AppKit

@MainActor
final class AppLifecycleCoordinator {
    struct StartupActions {
        let prepareApplication: @MainActor () -> Void
        let setupStatusItem: @MainActor () -> Void
        let applyInitialSettings: @MainActor () -> Void
        let installEventMonitors: @MainActor () -> Void
    }

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
        let shutdownCapture: @MainActor () async -> Void
        let recordingServiceLoaded: @MainActor () -> Bool
        let cancelRecording: @MainActor () -> Void
        let recordingServiceNeedsStop: @MainActor () -> Bool
        let stopRecording: @MainActor () async -> Void
        let recordingShutdownTimedOut: @MainActor () -> Void
        let stopCameraOverlay: @MainActor () -> Void
        let stopMagnifier: @MainActor () -> Void
        let cancelCaptureOverlay: @MainActor () -> Void
        let cancelCaptureEditor: @MainActor () -> Void
        let closePostCaptureActions: @MainActor () -> Void
        let closePinnedImages: @MainActor () -> Void
        let speechRecognitionServiceLoaded: @MainActor () -> Bool
        let cancelSpeechRecognition: @MainActor () -> Void
        let hideSpeechOverlay: @MainActor () -> Void
        let stopKeystrokeVisualizer: @MainActor () -> Void
        let systemMonitorServiceLoaded: @MainActor () -> Bool
        let stopSystemMonitor: @MainActor () -> Void
        let stopHealthReminder: @MainActor () -> Void
        let stopKeepAwake: @MainActor () async -> Void
        let stopClipboardMonitoring: @MainActor () -> Void
        let stopStatusItem: @MainActor () -> Void
        let stopDockIcon: @MainActor () -> Void
        let removeEventMonitors: @MainActor () -> Void
        let shutdownUploads: @MainActor () async -> Void
        let replyToTermination: @MainActor (NSApplication, Bool) -> Void
    }

    private let actions: Actions
    private let startupActions: StartupActions
    private let workspaceNotificationCenter: NotificationCenter
    private let recordingShutdownTimeout: Duration
    private var workspaceWakeObserver: NSObjectProtocol?
    private var workspaceSleepObserver: NSObjectProtocol?
    private var didFinishLaunching = false
    private var terminationShutdownStarted = false

    init(
        actions: Actions,
        startupActions: StartupActions,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        recordingShutdownTimeout: Duration = .seconds(30)
    ) {
        self.actions = actions
        self.startupActions = startupActions
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.recordingShutdownTimeout = recordingShutdownTimeout
    }

    func applicationDidFinishLaunching() {
        guard !didFinishLaunching else { return }
        didFinishLaunching = true

        startupActions.prepareApplication()
        startupActions.setupStatusItem()
        startupActions.applyInitialSettings()
        observeSystemPowerState()
        startupActions.installEventMonitors()
    }

    func observeSystemPowerState() {
        guard workspaceWakeObserver == nil, workspaceSleepObserver == nil else { return }

        workspaceWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.actions.systemDidWake()
            }
        }
        workspaceSleepObserver = workspaceNotificationCenter.addObserver(
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
            self?.actions.cancelUpload()
            if let self, self.actions.captureCoordinatorLoaded() {
                await self.actions.shutdownCapture()
            }
            if let self,
               self.actions.recordingServiceLoaded(),
               self.actions.recordingServiceNeedsStop()
            {
                self.actions.cancelRecording()
                guard await self.stopRecordingBeforeTermination() else {
                    self.terminationShutdownStarted = false
                    MeowLog.recording.error("Recording shutdown timed out; keeping the app running")
                    if let sender {
                        self.actions.replyToTermination(sender, false)
                    }
                    self.actions.recordingShutdownTimedOut()
                    return
                }
            }
            await self?.actions.stopKeepAwake()
            await self?.actions.shutdownUploads()
            if let sender {
                self?.actions.replyToTermination(sender, true)
            }
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
        if actions.recordingServiceLoaded(), actions.recordingServiceNeedsStop() {
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
        actions.stopStatusItem()
        actions.stopDockIcon()
        removeSystemPowerObservers()
        actions.removeEventMonitors()
    }

    private func removeSystemPowerObservers() {
        if let workspaceWakeObserver {
            workspaceNotificationCenter.removeObserver(workspaceWakeObserver)
            self.workspaceWakeObserver = nil
        }
        if let workspaceSleepObserver {
            workspaceNotificationCenter.removeObserver(workspaceSleepObserver)
            self.workspaceSleepObserver = nil
        }
    }

    private func stopRecordingBeforeTermination() async -> Bool {
        await withCheckedContinuation { continuation in
            let waiter = RecordingShutdownWaiter(continuation: continuation)
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: recordingShutdownTimeout)
                } catch {
                    return
                }
                await waiter.resolve(false)
            }
            Task { await waiter.setTimeoutTask(timeoutTask) }
            Task { @MainActor in
                await actions.stopRecording()
                await waiter.resolve(true)
            }
        }
    }
}

private actor RecordingShutdownWaiter {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isResolved = false

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        guard !isResolved else {
            task.cancel()
            return
        }
        timeoutTask = task
    }

    func resolve(_ completed: Bool) {
        guard !isResolved else { return }
        isResolved = true
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: completed)
        continuation = nil
    }
}
