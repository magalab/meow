import Foundation

@MainActor
final class AppHotkeyRouter {
    struct Actions {
        let settings: @MainActor () -> AppSettings
        let updateSettings: @MainActor (AppSettings) -> Void
        let toggleLauncher: @MainActor () -> Void
        let openFinder: @MainActor () -> Void
        let translate: @MainActor () -> Void
        let textActions: @MainActor () -> Void
        let scrollingScreenshot: @MainActor () -> Void
        let screenshot: @MainActor (ScreenshotCaptureMode, Bool, Bool) -> Void
        let recording: @MainActor (ScreenshotCaptureMode) -> Void
        let pauseRecording: @MainActor () -> Void
        let stopRecording: @MainActor () -> Void
        let saveRecordingFrame: @MainActor () -> Void
        let toggleRecordingMagnifier: @MainActor () -> Void
        let toggleWhiteboard: @MainActor () -> Void
        let speechPressed: @MainActor () -> Void
        let speechReleased: @MainActor () -> Void
        let setFinderRegistrationError: @MainActor (String?) -> Void
        let setWhiteboardRegistrationError: @MainActor (String?) -> Void
        let presentTextActionsHotkeyConflict: @MainActor (UInt32, UInt32) -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func makeCoordinatorActions() -> AppHotkeyCoordinator.Actions {
        AppHotkeyCoordinator.Actions(
            invoke: handle,
            restore: restore,
            registrationSucceeded: registrationSucceeded,
            registrationFailure: registrationFailure
        )
    }

    private func handle(_ event: AppHotkeyCoordinator.Event) {
        switch event {
        case .toggleLauncher:
            actions.toggleLauncher()
        case .openFinder:
            actions.openFinder()
        case .translate:
            actions.translate()
        case .textActions:
            actions.textActions()
        case .screenshotDefault:
            actions.screenshot(actions.settings().screenshot.defaultCaptureMode, false, false)
        case .screenshotDefaultAndEdit:
            actions.screenshot(actions.settings().screenshot.defaultCaptureMode, true, false)
        case .scrollingScreenshot:
            actions.scrollingScreenshot()
        case let .screenshot(mode):
            actions.screenshot(mode, false, false)
        case let .recording(mode):
            actions.recording(mode)
        case .pauseRecording:
            actions.pauseRecording()
        case .stopRecording:
            actions.stopRecording()
        case .saveRecordingFrame:
            actions.saveRecordingFrame()
        case .toggleRecordingMagnifier:
            actions.toggleRecordingMagnifier()
        case .uploadScreenshot:
            actions.screenshot(.region, false, true)
        case .toggleWhiteboard:
            actions.toggleWhiteboard()
        #if MEOW_VOICE
        case .speechPressed:
            actions.speechPressed()
        case .speechReleased:
            actions.speechReleased()
        #endif
        }
    }

    private func restore(_ kind: AppHotkeyCoordinator.Kind, keyCode: UInt32, modifiers: UInt32) {
        var settings = actions.settings()
        switch kind {
        case .launcher:
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
        case .finder:
            settings.finderHotkeyKeyCode = keyCode
            settings.finderHotkeyModifiers = modifiers
        case .translation:
            settings.translateHotkeyKeyCode = keyCode
            settings.translateHotkeyModifiers = modifiers
        case .textActions:
            settings.textActionsHotkeyKeyCode = keyCode
            settings.textActionsHotkeyModifiers = modifiers
        case .screenshotRegion:
            settings.screenshot.regionHotkeyKeyCode = keyCode
            settings.screenshot.regionHotkeyModifiers = modifiers
        case .screenshotScrolling:
            settings.screenshot.scrollingHotkeyKeyCode = keyCode
            settings.screenshot.scrollingHotkeyModifiers = modifiers
        case .screenshotEdit:
            settings.screenshot.editHotkeyKeyCode = keyCode
            settings.screenshot.editHotkeyModifiers = modifiers
        case .screenshotWindow:
            settings.screenshot.windowHotkeyKeyCode = keyCode
            settings.screenshot.windowHotkeyModifiers = modifiers
        case .screenshotDisplay:
            settings.screenshot.displayHotkeyKeyCode = keyCode
            settings.screenshot.displayHotkeyModifiers = modifiers
        case .recordingDisplay:
            settings.recording.displayHotkeyKeyCode = keyCode
            settings.recording.displayHotkeyModifiers = modifiers
        case .recordingRegion:
            settings.recording.regionHotkeyKeyCode = keyCode
            settings.recording.regionHotkeyModifiers = modifiers
        case .recordingWindow:
            settings.recording.windowHotkeyKeyCode = keyCode
            settings.recording.windowHotkeyModifiers = modifiers
        case .recordingPause:
            settings.recording.pauseHotkeyKeyCode = keyCode
            settings.recording.pauseHotkeyModifiers = modifiers
        case .recordingStop:
            settings.recording.stopHotkeyKeyCode = keyCode
            settings.recording.stopHotkeyModifiers = modifiers
        case .recordingFrame:
            settings.recording.frameHotkeyKeyCode = keyCode
            settings.recording.frameHotkeyModifiers = modifiers
        case .recordingMagnifier:
            settings.recording.magnifierHotkeyKeyCode = keyCode
            settings.recording.magnifierHotkeyModifiers = modifiers
        case .upload:
            settings.fileHosting.uploadHotkeyKeyCode = keyCode
            settings.fileHosting.uploadHotkeyModifiers = modifiers
        case .whiteboard:
            settings.whiteboard.hotkeyKeyCode = keyCode
            settings.whiteboard.hotkeyModifiers = modifiers
        #if MEOW_VOICE
        case .speech:
            settings.speech.hotkeyKeyCode = keyCode
            settings.speech.hotkeyModifiers = modifiers
        #endif
        }
        actions.updateSettings(settings)
    }

    private func registrationSucceeded(_ kind: AppHotkeyCoordinator.Kind) {
        switch kind {
        case .finder:
            actions.setFinderRegistrationError(nil)
        case .whiteboard:
            actions.setWhiteboardRegistrationError(nil)
        default:
            break
        }
    }

    private func registrationFailure(_ kind: AppHotkeyCoordinator.Kind, status: OSStatus) {
        switch kind {
        case .finder:
            actions.setFinderRegistrationError(String(format: L10n.prefsFinderHotkeyError, status))
        case .textActions:
            let settings = actions.settings()
            actions.presentTextActionsHotkeyConflict(
                settings.textActionsHotkeyKeyCode,
                settings.textActionsHotkeyModifiers
            )
        case .whiteboard:
            actions.setWhiteboardRegistrationError(String(format: L10n.whiteboardHotkeyError, status))
        default:
            break
        }
    }
}
