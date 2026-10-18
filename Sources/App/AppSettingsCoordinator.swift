import Foundation

@MainActor
final class AppSettingsCoordinator {
    struct RuntimeState {
        let aiChatHistoryStoreLoaded: Bool
        let captureStoreLoaded: Bool
        let recordingServiceLoaded: Bool
        let recordingStateShowsControls: Bool
        let authenticatorServiceLoaded: Bool
        let systemMonitorServiceLoaded: Bool
        let speechRecognitionServiceLoaded: Bool
    }

    struct Actions {
        let applyLanguage: @MainActor (AppLanguage, Bool) -> Void
        let applyDisplaySettings: @MainActor (AppSettings) -> Void
        let requestUploadNotificationAuthorization: @MainActor () -> Void
        let setAIChatHistoryPersistence: @MainActor (Bool) -> Void
        let applyCaptureRetention: @MainActor (ScreenshotSettings) -> Void
        let applyRecordingSettings: @MainActor (AppSettings) -> Void
        let setRecordingControlsVisible: @MainActor (Bool) -> Void
        let applyAuthenticatorSettings: @MainActor (AppSettings) -> Void
        let applySystemMonitorSettings: @MainActor (AppSettings) -> Void
        let applyAlwaysOnServices: @MainActor (AppSettings) -> Void
        let applySpeechSettings: @MainActor (AppSettings) -> Void
        let applyAutoLaunch: @MainActor (Bool) -> Bool
        let applyHotkeys: @MainActor (AppSettings) -> Void
        let applyWhiteboardSettings: @MainActor (AppSettings) -> Void
        let configureClipboard: @MainActor (AppSettings) -> Void
        let setClipboardMonitoring: @MainActor (Bool) -> Void
        let refreshLauncherAfterClipboardChange: @MainActor () -> Void
        let reconcileAutoLaunch: @MainActor (Bool) -> Void
    }

    private let actions: Actions
    private var appliedLanguage: AppLanguage?
    private var clipboardMonitoringEnabled = false
    private var uploadNotificationAuthorizationRequested = false

    init(actions: Actions) {
        self.actions = actions
    }

    func apply(settings: AppSettings, runtimeState: RuntimeState) {
        if appliedLanguage != settings.language {
            actions.applyLanguage(settings.language, runtimeState.systemMonitorServiceLoaded)
            appliedLanguage = settings.language
        }

        actions.applyDisplaySettings(settings)
        if settings.fileHosting.s3.isEnabled, !uploadNotificationAuthorizationRequested {
            uploadNotificationAuthorizationRequested = true
            actions.requestUploadNotificationAuthorization()
        }
        if runtimeState.aiChatHistoryStoreLoaded {
            actions.setAIChatHistoryPersistence(settings.ai.chatHistoryEnabled)
        }
        if runtimeState.captureStoreLoaded {
            actions.applyCaptureRetention(settings.screenshot)
        }
        if runtimeState.recordingServiceLoaded {
            actions.applyRecordingSettings(settings)
        }
        actions.setRecordingControlsVisible(
            runtimeState.recordingStateShowsControls && settings.recording.showFloatingControls
        )
        if settings.authenticatorEnabled || runtimeState.authenticatorServiceLoaded {
            actions.applyAuthenticatorSettings(settings)
        }
        if settings.systemMonitor.enabled || runtimeState.systemMonitorServiceLoaded {
            actions.applySystemMonitorSettings(settings)
        }
        actions.applyAlwaysOnServices(settings)
        #if MEOW_VOICE
        if settings.speech.enabled || runtimeState.speechRecognitionServiceLoaded {
            actions.applySpeechSettings(settings)
        }
        #endif

        let actualAutoLaunchEnabled = actions.applyAutoLaunch(settings.autoLaunch)
        actions.applyHotkeys(settings)
        actions.applyWhiteboardSettings(settings)
        actions.configureClipboard(settings)

        if settings.clipboardHistoryEnabled != clipboardMonitoringEnabled {
            actions.setClipboardMonitoring(settings.clipboardHistoryEnabled)
            clipboardMonitoringEnabled = settings.clipboardHistoryEnabled
            actions.refreshLauncherAfterClipboardChange()
        }

        if actualAutoLaunchEnabled != settings.autoLaunch {
            actions.reconcileAutoLaunch(actualAutoLaunchEnabled)
        }
    }
}
