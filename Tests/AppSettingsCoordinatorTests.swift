import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
@Test("Settings dispatch keeps disabled lazy services unloaded and deduplicates state transitions")
func settingsDispatchPreservesLazyServiceBoundaries() {
    let recorder = SettingsActionRecorder()
    let coordinator = AppSettingsCoordinator(actions: makeSettingsActions(recorder: recorder))
    var settings = AppSettings.default
    settings.clipboardHistoryEnabled = false
    let runtimeState = makeSettingsRuntimeState()

    coordinator.apply(settings: settings, runtimeState: runtimeState)
    coordinator.apply(settings: settings, runtimeState: runtimeState)

    #expect(recorder.calls.filter { $0.hasPrefix("language:") }.count == 1)
    #expect(recorder.calls.contains("language:monitor-unloaded"))
    #expect(recorder.calls.filter { $0 == "display" }.count == 2)
    #expect(recorder.calls.filter { $0 == "controls:hidden" }.count == 2)
    #expect(recorder.calls.filter { $0 == "alwaysOn" }.count == 2)
    #expect(!recorder.calls.contains("aiHistory"))
    #expect(!recorder.calls.contains("captureRetention"))
    #expect(!recorder.calls.contains("recording"))
    #expect(!recorder.calls.contains("authenticator"))
    #expect(!recorder.calls.contains("systemMonitor"))
    #expect(!recorder.calls.contains("speech"))
    #expect(!recorder.calls.contains { $0.hasPrefix("clipboardMonitoring:") })
}

@MainActor
@Test("Settings dispatch updates enabled or already-loaded services in stable order")
func settingsDispatchAppliesEnabledAndLoadedServices() {
    let recorder = SettingsActionRecorder()
    let coordinator = AppSettingsCoordinator(actions: makeSettingsActions(recorder: recorder))
    var settings = AppSettings.default
    settings.autoLaunch = true
    settings.fileHosting.s3.isEnabled = true
    settings.authenticatorEnabled = true
    settings.systemMonitor.enabled = true
    settings.recording.showFloatingControls = true
    let runtimeState = makeSettingsRuntimeState(allLoaded: true, recordingStateShowsControls: true)

    coordinator.apply(settings: settings, runtimeState: runtimeState)
    coordinator.apply(settings: settings, runtimeState: runtimeState)
    settings.clipboardHistoryEnabled = false
    coordinator.apply(settings: settings, runtimeState: runtimeState)

    #expect(recorder.calls.filter { $0 == "uploadAuthorization" }.count == 1)
    #expect(recorder.calls.filter { $0 == "aiHistory" }.count == 3)
    #expect(recorder.calls.filter { $0 == "captureRetention" }.count == 3)
    #expect(recorder.calls.filter { $0 == "recording" }.count == 3)
    #expect(recorder.calls.filter { $0 == "controls:visible" }.count == 3)
    #expect(recorder.calls.filter { $0 == "authenticator" }.count == 3)
    #expect(recorder.calls.filter { $0 == "systemMonitor" }.count == 3)
    #expect(recorder.calls.filter { $0 == "clipboardMonitoring:on" }.count == 1)
    #expect(recorder.calls.filter { $0 == "clipboardMonitoring:off" }.count == 1)
    #expect(recorder.calls.filter { $0 == "refreshAfterClipboardChange" }.count == 2)
    #expect(recorder.calls.filter { $0 == "reconcileAutoLaunch" }.count == 3)
    #if MEOW_VOICE
    #expect(recorder.calls.filter { $0 == "speech" }.count == 3)
    #endif
    func position(of action: String) -> Int { recorder.calls.firstIndex(of: action) ?? Int.max }
    #expect(recorder.calls.filter { $0.hasPrefix("language:") }.count == 1)
    #expect(recorder.calls.contains("language:monitor-loaded"))
    #expect(position(of: "language:monitor-loaded") < position(of: "display"))
    #expect(position(of: "recording") < position(of: "authenticator"))
    #expect(position(of: "hotkeys") < position(of: "whiteboard"))
    #expect(position(of: "clipboardMonitoring:on") < position(of: "refreshAfterClipboardChange"))
    #expect(
        (recorder.calls.lastIndex(of: "clipboardMonitoring:off") ?? -1) <
            (recorder.calls.lastIndex(of: "refreshAfterClipboardChange") ?? -1)
    )
    #expect(recorder.calls.last == "reconcileAutoLaunch")
}

@MainActor
@Test("Settings enable only the lazy services requested by the configuration")
func settingsEnableOnlyRequestedLazyServices() {
    let recorder = SettingsActionRecorder()
    let coordinator = AppSettingsCoordinator(actions: makeSettingsActions(recorder: recorder))
    var settings = AppSettings.default
    settings.authenticatorEnabled = true
    settings.systemMonitor.enabled = true
    settings.speech.enabled = true

    coordinator.apply(settings: settings, runtimeState: makeSettingsRuntimeState())

    #expect(recorder.calls.filter { $0 == "authenticator" }.count == 1)
    #expect(recorder.calls.filter { $0 == "systemMonitor" }.count == 1)
    #expect(!recorder.calls.contains("aiHistory"))
    #expect(!recorder.calls.contains("captureRetention"))
    #expect(!recorder.calls.contains("recording"))
    #if MEOW_VOICE
    #expect(recorder.calls.filter { $0 == "speech" }.count == 1)
    #else
    #expect(!recorder.calls.contains("speech"))
    #endif
}

@MainActor
private final class SettingsActionRecorder {
    var calls: [String] = []
}

@MainActor
private func makeSettingsRuntimeState(
    allLoaded: Bool = false,
    recordingStateShowsControls: Bool = false
) -> AppSettingsCoordinator.RuntimeState {
    AppSettingsCoordinator.RuntimeState(
        aiChatHistoryStoreLoaded: allLoaded,
        captureStoreLoaded: allLoaded,
        recordingServiceLoaded: allLoaded,
        recordingStateShowsControls: recordingStateShowsControls,
        authenticatorServiceLoaded: allLoaded,
        systemMonitorServiceLoaded: allLoaded,
        speechRecognitionServiceLoaded: allLoaded
    )
}

@MainActor
private func makeSettingsActions(recorder: SettingsActionRecorder) -> AppSettingsCoordinator.Actions {
    AppSettingsCoordinator.Actions(
        applyLanguage: { _, monitorLoaded in
            recorder.calls.append(monitorLoaded ? "language:monitor-loaded" : "language:monitor-unloaded")
        },
        applyDisplaySettings: { _ in recorder.calls.append("display") },
        requestUploadNotificationAuthorization: { recorder.calls.append("uploadAuthorization") },
        setAIChatHistoryPersistence: { _ in recorder.calls.append("aiHistory") },
        applyCaptureRetention: { _ in recorder.calls.append("captureRetention") },
        applyRecordingSettings: { _ in recorder.calls.append("recording") },
        setRecordingControlsVisible: { recorder.calls.append($0 ? "controls:visible" : "controls:hidden") },
        applyAuthenticatorSettings: { _ in recorder.calls.append("authenticator") },
        applySystemMonitorSettings: { _ in recorder.calls.append("systemMonitor") },
        applyAlwaysOnServices: { _ in recorder.calls.append("alwaysOn") },
        applySpeechSettings: { _ in recorder.calls.append("speech") },
        applyAutoLaunch: { _ in recorder.calls.append("autoLaunch"); return false },
        applyHotkeys: { _ in recorder.calls.append("hotkeys") },
        applyWhiteboardSettings: { _ in recorder.calls.append("whiteboard") },
        configureClipboard: { _ in recorder.calls.append("configureClipboard") },
        setClipboardMonitoring: { recorder.calls.append($0 ? "clipboardMonitoring:on" : "clipboardMonitoring:off") },
        refreshLauncherAfterClipboardChange: { recorder.calls.append("refreshAfterClipboardChange") },
        reconcileAutoLaunch: { _ in recorder.calls.append("reconcileAutoLaunch") }
    )
}
