import AppKit
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
struct AppMediaCommandRouterTests {
    @Test
    func captureAndRecordingActionsPreserveMediaCallbacks() async throws {
        let error = NSError(domain: "router-test", code: 1)
        var hiddenPanels = 0
        var capturePrepared = 0
        var captureRestored = 0
        var recordingPrepared = 0
        var recordingRestored = 0
        var screenshotErrors = 0
        var recordingErrors = 0
        var recordingStateUpdates = 0
        var audioModeSet = 0
        var uploadedURL: URL?
        let windowIDs: Set<CGWindowID> = [17]
        let router = AppMediaCommandRouter(actions: .init(
            settings: { .default },
            hideLauncher: {},
            hideTransientPanels: { hiddenPanels += 1 },
            prepareWhiteboardForCapture: { capturePrepared += 1; return windowIDs },
            restoreWhiteboardAfterCapture: { captureRestored += 1 },
            upload: { uploadedURL = $0 },
            refreshLauncher: {},
            presentScreenshotError: { _ in screenshotErrors += 1 },
            presentUploadError: { _ in },
            presentScrollingAccessibilityPrompt: {},
            presentScrollingReducedImageWarning: {},
            editImage: { _ in },
            recognizeClipboardImage: { _, _ in },
            scanClipboardImageQRCode: { _ in },
            askAI: { _ in },
            sendImageFileToWhiteboard: { _, _ in },
            captureIsBusy: { true },
            prepareWhiteboardForRecording: { recordingPrepared += 1; return windowIDs },
            restoreWhiteboardAfterRecording: { recordingRestored += 1 },
            activeScreen: { nil },
            setSystemAudioMode: { audioModeSet += 1 },
            updateRecordingState: { _, _ in recordingStateUpdates += 1 },
            presentRecordingError: { _ in recordingErrors += 1 }
        ))

        let capture = router.makeCaptureActions()
        capture.hideTransientPanels()
        #expect(capture.prepareWhiteboard() == windowIDs)
        capture.restoreWhiteboard()
        try await capture.upload(URL(fileURLWithPath: "/tmp/capture.png"))
        capture.presentScreenshotError(error)

        let recording = router.makeRecordingActions()
        #expect(recording.captureIsBusy())
        recording.hideTransientPanels()
        #expect(recording.prepareWhiteboard() == windowIDs)
        recording.restoreWhiteboard()
        recording.setSystemAudioMode()
        recording.updateRecordingState(.recording(startedAt: Date()), 2)
        recording.presentError(error)

        #expect(hiddenPanels == 2)
        #expect(capturePrepared == 1)
        #expect(captureRestored == 1)
        #expect(recordingPrepared == 1)
        #expect(recordingRestored == 1)
        #expect(screenshotErrors == 1)
        #expect(recordingErrors == 1)
        #expect(recordingStateUpdates == 1)
        #expect(audioModeSet == 1)
        #expect(uploadedURL == URL(fileURLWithPath: "/tmp/capture.png"))
    }
}
