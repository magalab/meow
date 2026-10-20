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
@Test("Termination shuts down Keep Awake and uploads before replying; repeat requests stay pending")
func lifecycleTerminationWaitsForShutdownAndRejectsRepeatedRequest() async {
    var calls: [String] = []
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _, _ in
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
        #expect(duplicateReply == .terminateLater)
    }

    #expect(calls == ["keepAwake", "uploads", "reply"])
}

@MainActor
@Test("Termination waits for canceled capture work before shutting down services")
func lifecycleTerminationWaitsForCaptureShutdown() async {
    var calls: [String] = []
    var captureContinuation: CheckedContinuation<Void, Never>?
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            cancelUpload: { calls.append("cancelUpload") },
            captureCoordinatorLoaded: { true },
            shutdownCapture: {
                calls.append("shutdownCapture")
                await withCheckedContinuation { captureContinuation = $0 }
            },
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _, shouldTerminate in
                calls.append("reply:\(shouldTerminate)")
                replyContinuation?.resume()
                replyContinuation = nil
            }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    let terminationTask = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            replyContinuation = continuation
            #expect(coordinator.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        }
    }
    for _ in 0..<10 where captureContinuation == nil { await Task.yield() }

    #expect(calls == ["cancelUpload", "shutdownCapture"])
    captureContinuation?.resume()
    await terminationTask.value

    #expect(calls == ["cancelUpload", "shutdownCapture", "keepAwake", "uploads", "reply:true"])
}

@MainActor
@Test("Termination awaits loaded speech recognition teardown before replying")
func lifecycleTerminationWaitsForSpeechRecognitionShutdown() async {
    var calls: [String] = []
    var shutdownContinuation: CheckedContinuation<Void, Never>?
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            cancelUpload: { calls.append("cancelUpload") },
            speechRecognitionServiceLoaded: { true },
            shutdownSpeechRecognition: {
                calls.append("shutdownSpeechRecognition")
                await withCheckedContinuation { shutdownContinuation = $0 }
            },
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _, _ in
                calls.append("reply")
                replyContinuation?.resume()
                replyContinuation = nil
            }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    let terminationTask = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            replyContinuation = continuation
            #expect(coordinator.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        }
    }
    for _ in 0..<10 where shutdownContinuation == nil { await Task.yield() }

    #expect(calls == ["cancelUpload", "shutdownSpeechRecognition"])
    shutdownContinuation?.resume()
    await terminationTask.value

    #expect(calls == ["cancelUpload", "shutdownSpeechRecognition", "keepAwake", "uploads", "reply"])
}

@MainActor
@Test("Termination waits for active recording teardown before allowing the app to exit")
func lifecycleTerminationWaitsForRecordingStop() async {
    var calls: [String] = []
    var stopContinuation: CheckedContinuation<Void, Never>?
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            recordingServiceLoaded: { true },
            cancelRecording: { calls.append("cancelRecording") },
            recordingServiceNeedsStop: { true },
            stopRecording: {
                calls.append("stopRecording")
                await withCheckedContinuation { stopContinuation = $0 }
            },
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _, _ in
                calls.append("reply")
                replyContinuation?.resume()
                replyContinuation = nil
            }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    let terminationTask = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            replyContinuation = continuation
            #expect(coordinator.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        }
    }
    for _ in 0..<10 where stopContinuation == nil { await Task.yield() }

    #expect(calls == ["cancelRecording", "stopRecording"])
    stopContinuation?.resume()
    await terminationTask.value

    #expect(calls == ["cancelRecording", "stopRecording", "keepAwake", "uploads", "reply"])
}

@MainActor
@Test("Termination waits for a recording that is already finishing")
func lifecycleTerminationWaitsForRecordingAlreadyFinishing() async {
    var calls: [String] = []
    var stopContinuation: CheckedContinuation<Void, Never>?
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            recordingServiceLoaded: { true },
            cancelRecording: { calls.append("cancelRecording") },
            recordingServiceNeedsStop: { true },
            stopRecording: {
                calls.append("joinRecordingStop")
                await withCheckedContinuation { stopContinuation = $0 }
            },
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _, _ in
                calls.append("reply")
                replyContinuation?.resume()
                replyContinuation = nil
            }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    let terminationTask = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            replyContinuation = continuation
            #expect(coordinator.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        }
    }
    for _ in 0..<10 where stopContinuation == nil { await Task.yield() }

    #expect(calls == ["cancelRecording", "joinRecordingStop"])
    stopContinuation?.resume()
    await terminationTask.value

    #expect(calls == ["cancelRecording", "joinRecordingStop", "keepAwake", "uploads", "reply"])
}

@MainActor
@Test("Recording shutdown timeout keeps the app running and permits a later quit")
func lifecycleRecordingShutdownTimeoutAllowsRetry() async {
    var calls: [String] = []
    var stopCalls = 0
    var firstStopContinuation: CheckedContinuation<Void, Never>?
    var replyContinuation: CheckedContinuation<Void, Never>?
    let coordinator = AppLifecycleCoordinator(
        actions: makeLifecycleTestActions(
            recordingServiceLoaded: { true },
            cancelRecording: { calls.append("cancelRecording") },
            recordingServiceNeedsStop: { true },
            stopRecording: {
                stopCalls += 1
                calls.append("stopRecording\(stopCalls)")
                if stopCalls == 1 {
                    await withCheckedContinuation { firstStopContinuation = $0 }
                }
            },
            recordingShutdownTimedOut: { calls.append("timeoutAlert") },
            stopKeepAwake: { calls.append("keepAwake") },
            shutdownUploads: { calls.append("uploads") },
            replyToTermination: { _, shouldTerminate in
                calls.append("reply:\(shouldTerminate)")
                replyContinuation?.resume()
                replyContinuation = nil
            }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter(),
        recordingShutdownTimeout: .milliseconds(20)
    )

    let firstTermination = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            replyContinuation = continuation
            #expect(coordinator.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        }
    }
    await firstTermination.value
    #expect(calls == ["cancelRecording", "stopRecording1", "reply:false", "timeoutAlert"])

    firstStopContinuation?.resume()
    for _ in 0..<10 { await Task.yield() }

    let secondTermination = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            replyContinuation = continuation
            #expect(coordinator.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        }
    }
    await secondTermination.value

    #expect(calls == [
        "cancelRecording", "stopRecording1", "reply:false", "timeoutAlert",
        "cancelRecording", "stopRecording2", "keepAwake", "uploads", "reply:true",
    ])
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
            recordingServiceNeedsStop: { false },
            stopKeystrokeVisualizer: { calls.append("keystrokeVisualizer") },
            stopHealthReminder: { calls.append("healthReminder") },
            stopClipboardMonitoring: { calls.append("clipboard") },
            stopStatusItem: { calls.append("statusItem") },
            stopDockIcon: { calls.append("dockIcon") },
            removeEventMonitors: { calls.append("eventMonitors") }
        ),
        startupActions: noOpStartupActions(),
        workspaceNotificationCenter: NotificationCenter()
    )

    coordinator.applicationWillTerminate()

    #expect(calls.starts(with: ["whiteboard", "hotkeys", "upload", "capture", "recording"]))
    #expect(calls.suffix(6) == [
        "keystrokeVisualizer", "healthReminder", "clipboard", "statusItem", "dockIcon", "eventMonitors",
    ])
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
    shutdownCapture: @escaping @MainActor () async -> Void = {},
    recordingServiceLoaded: @escaping @MainActor () -> Bool = { false },
    cancelRecording: @escaping @MainActor () -> Void = {},
    recordingServiceNeedsStop: @escaping @MainActor () -> Bool = { false },
    stopRecording: @escaping @MainActor () async -> Void = {},
    recordingShutdownTimedOut: @escaping @MainActor () -> Void = {},
    stopCameraOverlay: @escaping @MainActor () -> Void = {},
    stopMagnifier: @escaping @MainActor () -> Void = {},
    cancelCaptureOverlay: @escaping @MainActor () -> Void = {},
    cancelCaptureEditor: @escaping @MainActor () -> Void = {},
    closePostCaptureActions: @escaping @MainActor () -> Void = {},
    closePinnedImages: @escaping @MainActor () -> Void = {},
    speechRecognitionServiceLoaded: @escaping @MainActor () -> Bool = { false },
    cancelSpeechRecognition: @escaping @MainActor () -> Void = {},
    shutdownSpeechRecognition: @escaping @MainActor () async -> Void = {},
    hideSpeechOverlay: @escaping @MainActor () -> Void = {},
    stopKeystrokeVisualizer: @escaping @MainActor () -> Void = {},
    systemMonitorServiceLoaded: @escaping @MainActor () -> Bool = { false },
    stopSystemMonitor: @escaping @MainActor () -> Void = {},
    stopHealthReminder: @escaping @MainActor () -> Void = {},
    stopKeepAwake: @escaping @MainActor () async -> Void = {},
    stopClipboardMonitoring: @escaping @MainActor () -> Void = {},
    stopStatusItem: @escaping @MainActor () -> Void = {},
    stopDockIcon: @escaping @MainActor () -> Void = {},
    removeEventMonitors: @escaping @MainActor () -> Void = {},
    shutdownUploads: @escaping @MainActor () async -> Void = {},
    replyToTermination: @escaping @MainActor (NSApplication, Bool) -> Void = { _, _ in }
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
        shutdownCapture: shutdownCapture,
        recordingServiceLoaded: recordingServiceLoaded,
        cancelRecording: cancelRecording,
        recordingServiceNeedsStop: recordingServiceNeedsStop,
        stopRecording: stopRecording,
        recordingShutdownTimedOut: recordingShutdownTimedOut,
        stopCameraOverlay: stopCameraOverlay,
        stopMagnifier: stopMagnifier,
        cancelCaptureOverlay: cancelCaptureOverlay,
        cancelCaptureEditor: cancelCaptureEditor,
        closePostCaptureActions: closePostCaptureActions,
        closePinnedImages: closePinnedImages,
        speechRecognitionServiceLoaded: speechRecognitionServiceLoaded,
        cancelSpeechRecognition: cancelSpeechRecognition,
        shutdownSpeechRecognition: shutdownSpeechRecognition,
        hideSpeechOverlay: hideSpeechOverlay,
        stopKeystrokeVisualizer: stopKeystrokeVisualizer,
        systemMonitorServiceLoaded: systemMonitorServiceLoaded,
        stopSystemMonitor: stopSystemMonitor,
        stopHealthReminder: stopHealthReminder,
        stopKeepAwake: stopKeepAwake,
        stopClipboardMonitoring: stopClipboardMonitoring,
        stopStatusItem: stopStatusItem,
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
