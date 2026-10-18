import AppKit
import ApplicationServices

@MainActor
struct AppMediaCommandRouter {
    struct Actions {
        let settings: @MainActor () -> AppSettings
        let hideTransientPanels: @MainActor () -> Void
        let prepareWhiteboardForCapture: @MainActor () -> Set<CGWindowID>
        let restoreWhiteboardAfterCapture: @MainActor () -> Void
        let upload: @MainActor (URL) async throws -> Void
        let refreshLauncher: @MainActor () -> Void
        let presentScreenshotError: @MainActor (Error) -> Void
        let presentUploadError: @MainActor (Error) -> Void
        let presentScrollingAccessibilityPrompt: @MainActor () -> Void
        let presentScrollingReducedImageWarning: @MainActor () -> Void
        let editImage: @MainActor (URL) -> Void
        let recognizeClipboardImage: @MainActor (ImageClipboardContent, Bool) -> Void
        let scanClipboardImageQRCode: @MainActor (ImageClipboardContent) -> Void
        let askAI: @MainActor (URL) -> Void
        let sendImageFileToWhiteboard: @MainActor (URL, String?) -> Void
        let captureIsBusy: @MainActor () -> Bool
        let prepareWhiteboardForRecording: @MainActor () -> Set<CGWindowID>
        let restoreWhiteboardAfterRecording: @MainActor () -> Void
        let activeScreen: @MainActor () -> NSScreen?
        let setSystemAudioMode: @MainActor () -> Void
        let presentRecordingError: @MainActor (Error) -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func makeCaptureActions() -> AppCaptureCoordinator.Actions {
        AppCaptureCoordinator.Actions(
            settings: actions.settings,
            hideTransientPanels: actions.hideTransientPanels,
            prepareWhiteboard: actions.prepareWhiteboardForCapture,
            restoreWhiteboard: actions.restoreWhiteboardAfterCapture,
            upload: actions.upload,
            refreshLauncher: actions.refreshLauncher,
            presentScreenshotError: actions.presentScreenshotError,
            presentUploadError: actions.presentUploadError,
            presentScrollingAccessibilityPrompt: actions.presentScrollingAccessibilityPrompt,
            presentScrollingReducedImageWarning: actions.presentScrollingReducedImageWarning,
            editImage: actions.editImage,
            recognizeClipboardImage: actions.recognizeClipboardImage,
            scanClipboardImageQRCode: actions.scanClipboardImageQRCode,
            askAI: actions.askAI,
            sendImageFileToWhiteboard: actions.sendImageFileToWhiteboard
        )
    }

    func makeRecordingActions() -> AppRecordingCoordinator.Actions {
        AppRecordingCoordinator.Actions(
            settings: actions.settings,
            captureIsBusy: actions.captureIsBusy,
            hideTransientPanels: actions.hideTransientPanels,
            prepareWhiteboard: actions.prepareWhiteboardForRecording,
            restoreWhiteboard: actions.restoreWhiteboardAfterRecording,
            activeScreen: actions.activeScreen,
            setSystemAudioMode: actions.setSystemAudioMode,
            presentError: actions.presentRecordingError
        )
    }
}
