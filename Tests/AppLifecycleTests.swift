import AppKit
import Foundation
import Testing

#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
@Test("Lifecycle startup preserves order and ignores duplicate launch callbacks")
func lifecycleStartupIsOrderedAndIdempotent() {
    var calls: [String] = []
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(),
        startupActions: AppLifecycleCoordinator.StartupActions(
            prepareApplication: { calls.append("prepare") },
            setupStatusItem: { calls.append("statusItem") },
            applyInitialSettings: { calls.append("settings") },
            installEventMonitors: { calls.append("eventMonitors") }
        ),
        workspaceNotificationCenter: NotificationCenter()
    )

    coordinator.applicationDidFinishLaunching()
    coordinator.applicationDidFinishLaunching()

    #expect(calls == ["prepare", "statusItem", "settings", "eventMonitors"])
}

@MainActor
@Test("Lifecycle power observers register once and are removed at termination")
func lifecyclePowerObserversAreIdempotentAndRemoved() async {
    var wakeCalls = 0
    var sleepCalls = 0
    let notificationCenter = NotificationCenter()
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            systemDidWake: { wakeCalls += 1 },
            systemWillSleep: { sleepCalls += 1 }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: notificationCenter
    )

    coordinator.observeSystemPowerState()
    coordinator.observeSystemPowerState()
    notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<10 { await Task.yield() }

    #expect(wakeCalls == 1)
    #expect(sleepCalls == 1)

    coordinator.applicationWillTerminate()
    notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<10 { await Task.yield() }

    #expect(wakeCalls == 1)
    #expect(sleepCalls == 1)
}

@MainActor
@Test("Termination shuts down Keep Awake and uploads before replying and only starts once")
func lifecycleTerminationWaitsForShutdownAndRejectsRepeatedRequest() async {
    var calls: [String] = []
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _ in
                calls.append("reply")
                replyContinuation?.resume()
                replyContinuation = nil
            }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        replyContinuation = continuation
        let firstReply = coordinator.applicationShouldTerminate(NSApplication.shared)
        let duplicateReply = coordinator.applicationShouldTerminate(NSApplication.shared)
        #expect(firstReply == .terminateLater)
        #expect(duplicateReply == .terminateNow)
    }

    #expect(calls == ["keepAwake", "uploads", "reply"])
}

@MainActor
@Test("Application termination cancels active feature work before removing monitors")
func lifecycleTerminationCancelsFeaturesBeforeMonitors() {
    var calls: [String] = []
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            shutdownWhiteboard: { calls.append("whiteboard") },
            unregisterHotkeys: { calls.append("hotkeys") },
            cancelUpload: { calls.append("upload") },
            captureCoordinatorLoaded: { true },
            cancelCapture: { calls.append("capture") },
            recordingServiceLoaded: { true },
            cancelRecording: { calls.append("recording") },
            recordingServiceIsActive: { false },
            stopKeystrokeVisualizer: { calls.append("keystrokeVisualizer") },
            stopHealthReminder: { calls.append("healthReminder") },
            stopClipboardMonitoring: { calls.append("clipboard") },
            stopDockIcon: { calls.append("dockIcon") },
            removeEventMonitors: { calls.append("eventMonitors") }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    coordinator.applicationWillTerminate()

    #expect(calls.starts(with: ["whiteboard", "hotkeys", "upload", "capture", "recording"]))
    #expect(calls.suffix(5) == ["keystrokeVisualizer", "healthReminder", "clipboard", "dockIcon", "eventMonitors"])
}

@MainActor
private func makeLifecycleTestActions(
    systemDidWake: @escaping @MainActor () -> Void = {},
    systemWillSleep: @escaping @MainActor () -> Void = {},
    retryPermissions: @escaping @MainActor () -> Void = {},
    refreshSpeechPermission: @escaping @MainActor () -> Void = {},
    shutdownWhiteboard: @escaping @MainActor () -> Void = {},
    unregisterHotkeys: @escaping @MainActor () -> Void = {},
    cancelUpload: @escaping @MainActor () -> Void = {},
    captureCoordinatorLoaded: @escaping @MainActor () -> Bool = { false },
    cancelCapture: @escaping @MainActor () -> Void = {},
    recordingServiceLoaded: @escaping @MainActor () -> Bool = { false },
    cancelRecording: @escaping @MainActor () -> Void = {},
    recordingServiceIsActive: @escaping @MainActor () -> Bool = { false },
    stopRecording: @escaping @MainActor () async -> Void = {},
    stopCameraOverlay: @escaping @MainActor () -> Void = {},
    stopMagnifier: @escaping @MainActor () -> Void = {},
    cancelCaptureOverlay: @escaping @MainActor () -> Void = {},
    cancelCaptureEditor: @escaping @MainActor () -> Void = {},
    closePostCaptureActions: @escaping @MainActor () -> Void = {},
    closePinnedImages: @escaping @MainActor () -> Void = {},
    speechRecognitionServiceLoaded: @escaping @MainActor () -> Bool = { false },
    cancelSpeechRecognition: @escaping @MainActor () -> Void = {},
    hideSpeechOverlay: @escaping @MainActor () -> Void = {},
    stopKeystrokeVisualizer: @escaping @MainActor () -> Void = {},
    systemMonitorServiceLoaded: @escaping @MainActor () -> Bool = { false },
    stopSystemMonitor: @escaping @MainActor () -> Void = {},
    stopHealthReminder: @escaping @MainActor () -> Void = {},
    stopKeepAwake: @escaping @MainActor () async -> Void = {},
    stopClipboardMonitoring: @escaping @MainActor () -> Void = {},
    stopDockIcon: @escaping @MainActor () -> Void = {},
    removeEventMonitors: @escaping @MainActor () -> Void = {},
    shutdownUploads: @escaping @MainActor () async -> Void = {},
    replyToTermination: @escaping @MainActor (NSApplication) -> Void = { _ in }
) -> AppLifecycleCoordinator.Actions {
    AppLifecycleCoordinator.Actions(
        systemDidWake: systemDidWake,
        systemWillSleep: systemWillSleep,
        retryPermissions: retryPermissions,
        refreshSpeechPermission: refreshSpeechPermission,
        shutdownWhiteboard: shutdownWhiteboard,
        unregisterHotkeys: unregisterHotkeys,
        cancelUpload: cancelUpload,
        captureCoordinatorLoaded: captureCoordinatorLoaded,
        cancelCapture: cancelCapture,
        recordingServiceLoaded: recordingServiceLoaded,
        cancelRecording: cancelRecording,
        recordingServiceIsActive: recordingServiceIsActive,
        stopRecording: stopRecording,
        stopCameraOverlay: stopCameraOverlay,
        stopMagnifier: stopMagnifier,
        cancelCaptureOverlay: cancelCaptureOverlay,
        cancelCaptureEditor: cancelCaptureEditor,
        closePostCaptureActions: closePostCaptureActions,
        closePinnedImages: closePinnedImages,
        speechRecognitionServiceLoaded: speechRecognitionServiceLoaded,
        cancelSpeechRecognition: cancelSpeechRecognition,
        hideSpeechOverlay: hideSpeechOverlay,
        stopKeystrokeVisualizer: stopKeystrokeVisualizer,
        systemMonitorServiceLoaded: systemMonitorServiceLoaded,
        stopSystemMonitor: stopSystemMonitor,
        stopHealthReminder: stopHealthReminder,
        stopKeepAwake: stopKeepAwake,
        stopClipboardMonitoring: stopClipboardMonitoring,
        stopDockIcon: stopDockIcon,
        removeEventMonitors: removeEventMonitors,
        shutdownUploads: shutdownUploads,
        replyToTermination: replyToTermination
    )
}

@MainActor
private func noOpStartupActions() -> AppLifecycleCoordinator.StartupActions {
    AppLifecycleCoordinator.StartupActions(
        prepareApplication: {},
        setupStatusItem: {},
        applyInitialSettings: {},
        installEventMonitors: {}
    )
}
