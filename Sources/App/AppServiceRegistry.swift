import AppKit
import WhiteboardFeature

@MainActor
final class AppServiceRegistry {
    let settingsStore = SettingsStore()
    let dockService = DockService()
    let dockIconService = DockIconService()
    let statusItemService = StatusItemService()
    let discoveryService = AppDiscoveryService()
    let launchHistoryStore = LaunchHistoryStore()
    let autoLaunchService = AutoLaunchService()
    let keystrokeVisualizerService = KeystrokeVisualizerService()
    let whiteboardFeatureController = WhiteboardFeatureController()
    let healthReminderService = HealthReminderService()
    let keepAwakeService = KeepAwakeService()
    let clipboardStore = ClipboardStore()
    let captureOverlayController = CaptureOverlayController()
    let scrollingCaptureHUDController = ScrollingCaptureHUDController()
    lazy var recordingStore = RecordingStore()
    lazy var recordingNotificationService = RecordingNotificationService()
    let cameraOverlayController = CameraOverlayController()
    let screenMagnifierController = ScreenMagnifierController()
    let uploadSuccessHUDController = UploadSuccessHUDController()
    lazy var pinnedImageController = PinnedImageController()
    lazy var imageRecognitionService = ImageRecognitionService()
    lazy var preferencesNavigation = PreferencesNavigationState()
    let translationService = TranslationService()
    let textServiceProvider = TextServiceProvider()

    lazy var screenCaptureService = ScreenCaptureService()
    lazy var recordingContentPickerController = RecordingContentPickerController()
}
