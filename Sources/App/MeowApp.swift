import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
@preconcurrency import ScreenCaptureKit
import SwiftUI
import WhiteboardFeature
@main
struct MeowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.menuPreferences) {
                    (NSApp.delegate as? AppDelegate)?.openPreferencesFromCommand()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceRegistry = AppServiceRegistry()

    private var settingsStore: SettingsStore { serviceRegistry.settingsStore }
    private var dockService: DockService { serviceRegistry.dockService }
    private var dockIconService: DockIconService { serviceRegistry.dockIconService }
    private var statusItemService: StatusItemService { serviceRegistry.statusItemService }
    private var discoveryService: AppDiscoveryService { serviceRegistry.discoveryService }
    private var launchHistoryStore: LaunchHistoryStore { serviceRegistry.launchHistoryStore }
    private var autoLaunchService: AutoLaunchService { serviceRegistry.autoLaunchService }
    private lazy var hotkeyCoordinator = AppHotkeyCoordinator(hotkeyService: HotkeyService())
    private var keystrokeVisualizerService: KeystrokeVisualizerService {
        serviceRegistry.keystrokeVisualizerService
    }
    private var whiteboardFeatureController: WhiteboardFeatureController {
        serviceRegistry.whiteboardFeatureController
    }
    private var authenticatorServiceLoaded = false
    private lazy var authenticatorService: AuthenticatorService = {
        authenticatorServiceLoaded = true
        let service = AuthenticatorService()
        configureAuthenticatorService(service)
        service.apply(
            enabled: viewModel.settings.authenticatorEnabled,
            iCloudSyncEnabled: viewModel.settings.authenticatorICloudSyncEnabled,
            theme: viewModel.settings.theme
        )
        return service
    }()
    private var systemMonitorServiceLoaded = false
    private lazy var systemMonitorService: SystemMonitorService = {
        systemMonitorServiceLoaded = true
        let service = SystemMonitorService()
        service.apply(settings: viewModel.settings.systemMonitor, theme: viewModel.settings.theme)
        return service
    }()
    private var healthReminderService: HealthReminderService { serviceRegistry.healthReminderService }
    private var keepAwakeService: KeepAwakeService { serviceRegistry.keepAwakeService }
    private var clipboardStore: ClipboardStore { serviceRegistry.clipboardStore }
    private var screenCaptureService: ScreenCaptureService { serviceRegistry.screenCaptureService }
    private var captureOverlayController: CaptureOverlayController {
        serviceRegistry.captureOverlayController
    }
    private var scrollingCaptureHUDController: ScrollingCaptureHUDController {
        serviceRegistry.scrollingCaptureHUDController
    }
    private var recordingContentPickerController: RecordingContentPickerController {
        serviceRegistry.recordingContentPickerController
    }
    private var captureStoreLoaded = false
    private lazy var captureStore: CaptureStore = {
        captureStoreLoaded = true
        let store = CaptureStore()
        configureCaptureStore(store)
        let settings = viewModel.settings.screenshot
        store.applyRetention(
            historyLimit: settings.historyLimit,
            retentionDays: settings.retentionDays,
            maxStorageMB: settings.maxStorageMB
        )
        return store
    }()
    private var captureCoordinatorLoaded = false
    private lazy var captureCoordinator: AppCaptureCoordinator = {
        captureCoordinatorLoaded = true
        return AppCaptureCoordinator(
            screenCaptureService: screenCaptureService,
            captureOverlayController: captureOverlayController,
            captureEditorController: captureEditorController,
            captureStore: captureStore,
            scrollingCaptureHUDController: scrollingCaptureHUDController,
            imageRecognitionService: imageRecognitionService,
            clipboardStore: clipboardStore,
            pinnedImageController: pinnedImageController,
            postCaptureActionsController: postCaptureActionsController,
            windowCoordinator: windowCoordinator,
            actions: makeCaptureActions()
        )
    }()

    private var captureIsBusy: Bool {
        captureCoordinatorLoaded && captureCoordinator.isBusy
    }
    private lazy var clipboardActionCoordinator: AppClipboardActionCoordinator = {
        return AppClipboardActionCoordinator(
            imageRecognitionService: imageRecognitionService,
            captureEditorController: captureEditorController,
            captureCoordinator: captureCoordinator,
            fileUploadService: fileUploadService,
            actions: makeClipboardActions()
        )
    }()
    private var recordingStore: RecordingStore { serviceRegistry.recordingStore }
    private var recordingServiceLoaded = false
    private lazy var recordingService: RecordingService = {
        recordingServiceLoaded = true
        let service = RecordingService(store: recordingStore)
        configureRecordingService(service)
        service.apply(settings: viewModel.settings)
        recordingNotificationService.requestAuthorization()
        return service
    }()
    private lazy var recordingCoordinator = AppRecordingCoordinator(
        screenCaptureService: screenCaptureService,
        captureOverlayController: captureOverlayController,
        recordingContentPickerController: recordingContentPickerController,
        recordingService: recordingService,
        recordingStore: recordingStore,
        cameraOverlayController: cameraOverlayController,
        screenMagnifierController: screenMagnifierController,
        windowCoordinator: windowCoordinator,
        actions: makeRecordingActions()
    )
    private var recordingNotificationService: RecordingNotificationService {
        serviceRegistry.recordingNotificationService
    }
    private var cameraOverlayController: CameraOverlayController {
        serviceRegistry.cameraOverlayController
    }
    private var screenMagnifierController: ScreenMagnifierController {
        serviceRegistry.screenMagnifierController
    }
    private lazy var captureEditorController = CaptureEditorController()
    private lazy var postCaptureActionsController = PostCaptureActionsController()
    private lazy var uploadHistoryStore = UploadHistoryStore()
    private var uploadSuccessHUDController: UploadSuccessHUDController {
        serviceRegistry.uploadSuccessHUDController
    }
    private lazy var fileUploadService = FileUploadService(
        historyStore: uploadHistoryStore,
        settings: { [weak self] in self?.viewModel.settings.fileHosting ?? .default },
        notifySuccess: { [weak self] filename in
            FileUploadNotifications.notifySuccess(filename: filename)
            self?.uploadSuccessHUDController.show(
                filename: filename,
                relativeTo: self?.statusItemService.statusItemButton
            )
        }
    )
    private var pinnedImageController: PinnedImageController { serviceRegistry.pinnedImageController }
    private var imageRecognitionService: ImageRecognitionService {
        serviceRegistry.imageRecognitionService
    }
    private var preferencesNavigation: PreferencesNavigationState {
        serviceRegistry.preferencesNavigation
    }
    private var aiChatHistoryStoreLoaded = false
    private lazy var aiChatHistoryStore: AIChatHistoryStore = {
        aiChatHistoryStoreLoaded = true
        let store = AIChatHistoryStore()
        store.setPersistenceEnabled(viewModel.settings.ai.chatHistoryEnabled)
        return store
    }()
    #if MEOW_VOICE
    private lazy var speechModelStore = SpeechModelStore()
    private lazy var speechHistoryStore = SpeechHistoryStore()
    private lazy var ttsModelStore = TtsModelStore()
    private var speechRecognitionServiceLoaded = false
    private lazy var speechRecognitionService: SpeechRecognitionService = {
        speechRecognitionServiceLoaded = true
        let service = SpeechRecognitionService(
            modelStore: speechModelStore,
            historyStore: speechHistoryStore,
            clipboardStore: clipboardStore
        )
        service.onNeedsModel = { [weak self] in
            self?.showPreferences(section: .speech)
        }
        speechOverlayController.connect(to: service)
        service.apply(settings: viewModel.settings.speech)
        return service
    }()
    private var speechSynthesisServiceLoaded = false
    private lazy var speechSynthesisService: SpeechSynthesisService = {
        speechSynthesisServiceLoaded = true
        let service = SpeechSynthesisService(modelStore: ttsModelStore)
        service.onNeedsModel = { [weak self] in
            self?.showPreferences(section: .speech)
        }
        service.apply(settings: viewModel.settings.tts.normalized())
        return service
    }()
    private let speechOverlayController = SpeechOverlayController()
    #endif

    private var translationService: TranslationService { serviceRegistry.translationService }
    private var textServiceProvider: TextServiceProvider { serviceRegistry.textServiceProvider }
    private lazy var textActionCoordinator = AppTextActionCoordinator(
        translationService: translationService,
        windowCoordinator: windowCoordinator,
        actions: makeTextActions()
    )

    private let windowCoordinator = AppWindowCoordinator()
    private lazy var lifecycleCoordinator = AppLifecycleCoordinator(
        actions: makeLifecycleActions()
    )
    private lazy var preferencesCoordinator: AppPreferencesCoordinator = {
        #if MEOW_VOICE
        let dependencies = AppPreferencesCoordinator.Dependencies(
            viewModel: viewModel,
            clipboardStore: clipboardStore,
            navigation: preferencesNavigation,
            aiChatHistoryStore: aiChatHistoryStore,
            keystrokeVisualizerService: keystrokeVisualizerService,
            authenticatorService: authenticatorService,
            healthReminderService: healthReminderService,
            keepAwakeService: keepAwakeService,
            fileUploadService: fileUploadService,
            recordingStore: recordingStore,
            makeCaptureHistoryView: { [weak self] theme in
                self?.makeCaptureHistoryView(theme: theme) ?? CaptureHistoryView(
                    store: CaptureStore(),
                    theme: theme,
                    onCopy: { _ in },
                    onPin: { _ in },
                    onEdit: { _ in },
                    onRecognizeText: { _ in },
                    onTranslate: { _ in },
                    onScanQRCode: { _ in },
                    onAskAI: { _ in },
                    onSendToWhiteboard: nil,
                    onDelete: { _ in },
                    onClear: {}
                )
            },
            showRecordingTrimmer: { [weak self] url in
                self?.showRecordingTrimmer(for: url)
            },
            speechModelStore: speechModelStore,
            speechHistoryStore: speechHistoryStore,
            speechRecognitionService: speechRecognitionService,
            ttsModelStore: ttsModelStore,
            speechSynthesisService: speechSynthesisService
        )
        return AppPreferencesCoordinator(windowCoordinator: windowCoordinator, dependencies: dependencies)
        #else
        let dependencies = AppPreferencesCoordinator.Dependencies(
            viewModel: viewModel,
            clipboardStore: clipboardStore,
            navigation: preferencesNavigation,
            aiChatHistoryStore: aiChatHistoryStore,
            keystrokeVisualizerService: keystrokeVisualizerService,
            authenticatorService: authenticatorService,
            healthReminderService: healthReminderService,
            keepAwakeService: keepAwakeService,
            fileUploadService: fileUploadService,
            recordingStore: recordingStore,
            makeCaptureHistoryView: { [weak self] theme in
                self?.makeCaptureHistoryView(theme: theme) ?? CaptureHistoryView(
                    store: CaptureStore(),
                    theme: theme,
                    onCopy: { _ in },
                    onPin: { _ in },
                    onEdit: { _ in },
                    onRecognizeText: { _ in },
                    onTranslate: { _ in },
                    onScanQRCode: { _ in },
                    onAskAI: { _ in },
                    onSendToWhiteboard: nil,
                    onDelete: { _ in },
                    onClear: {}
                )
            },
            showRecordingTrimmer: { [weak self] url in
                self?.showRecordingTrimmer(for: url)
            }
        )
        return AppPreferencesCoordinator(windowCoordinator: windowCoordinator, dependencies: dependencies)
        #endif
    }()
    private var viewModel: LauncherViewModel!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    #if MEOW_VOICE
    private var selectedTextForTts = ""
    private var ttsSelectionPermissionDenied = false
    #endif
    private var appliedLanguage: AppLanguage?
    private var whiteboardPreparedForRecording = false
    private var clipboardMonitoringEnabled = false
    private var calendarRefreshToken = UUID()
    private var uploadNotificationAuthorizationRequested = false

    func applicationDidFinishLaunching(_: Notification) {
        viewModel = LauncherViewModel(
            settingsStore: settingsStore,
            discoveryService: discoveryService,
            launchHistoryStore: launchHistoryStore,
            clipboardStore: clipboardStore
        )
        viewModel.onOpenPreferences = { [weak self] in
            self?.showPreferences()
        }
        viewModel.onOpenAIChat = { [weak self] input in
            self?.openAIChat(input)
        }
        viewModel.onOpenAuthenticator = { [weak self] in
            self?.hideLauncher()
            self?.authenticatorService.showPanel()
        }
        viewModel.onHealthCommand = { [weak self] command in
            self?.handleHealthCommand(command)
        }
        viewModel.onScreenshotCommand = { [weak self] command in
            self?.handleScreenshotCommand(command)
        }
        viewModel.onRecordingCommand = { [weak self] command in
            self?.handleRecordingCommand(command)
        }
        viewModel.onWhiteboardCommand = { [weak self] command in
            self?.handleWhiteboardCommand(command)
        }
        viewModel.onKeepAwakeCommand = { [weak self] in
            self?.handleKeepAwakeCommand()
        }
        keepAwakeService.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.viewModel.updateKeepAwakeState(
                state,
                remainingMinutes: self.keepAwakeService.remainingMinutes
            )
        }
        keepAwakeService.onRemainingTimeChanged = { [weak self] remainingMinutes in
            guard let self else { return }
            self.viewModel.updateKeepAwakeState(
                self.keepAwakeService.state,
                remainingMinutes: remainingMinutes
            )
        }
        viewModel.onUploadClipboard = { [weak self] in
            self?.hideLauncher()
            self?.uploadFromClipboard()
        }
        #if MEOW_VOICE
        viewModel.onSpeakText = { [weak self] text in
            guard let self else { return }
            self.hideLauncher()
            self.speechSynthesisService.synthesize(text: text, settings: self.viewModel.settings.tts)
        }
        viewModel.onSpeakSelectedText = { [weak self] in
            self?.speakCapturedSelection()
        }
        #endif
        viewModel.onPinClipboardImage = { [weak self] image in
            self?.hideLauncher()
            self?.pinnedImageController.pin(image)
        }
        viewModel.onRecognizeClipboardImage = { [weak self] image in
            self?.recognizeClipboardImage(image, translate: false)
        }
        viewModel.onTranslateClipboardImage = { [weak self] image in
            self?.recognizeClipboardImage(image, translate: true)
        }
        viewModel.onScanClipboardImageQRCode = { [weak self] image in
            self?.scanClipboardImageQRCode(image)
        }
        viewModel.onEditClipboardImage = { [weak self] image in
            self?.editClipboardImage(image)
        }
        viewModel.onOpenClipboardImage = { [weak self] image in
            self?.openClipboardImage(image)
        }
        viewModel.onSaveClipboardImage = { [weak self] image in
            self?.saveClipboardImageAs(image)
        }
        viewModel.onSendClipboardImageToWhiteboard = { [weak self] image in
            self?.sendImageToWhiteboard(image)
        }
        viewModel.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
        }
        whiteboardFeatureController.onError = { [weak self] error in
            NSLog("[Meow Whiteboard] %@", error.localizedDescription)
            self?.presentWhiteboardError(error.localizedDescription)
        }
        keystrokeVisualizerService.onOverlayPlacementChanged = { [weak self] position, point in
            guard let self else { return }
            guard self.viewModel.settings.keystrokeVisualizerOverlayPosition != position ||
                self.viewModel.settings.keystrokeVisualizerOverlayPoint != point
            else { return }

            self.viewModel.updateKeystrokeOverlayPlacement(position: position, point: point)
        }
        viewModel.onPasteClipboard = { [weak self] entry in
            guard let self else { return }
            // Hide launcher first so target app becomes frontmost
            self.hideLauncher()
            // Small delay to let hide complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.clipboardStore.writeToPasteboard(entry)
                self.simulatePaste()
            }
        }
        viewModel.onLaunchApplication = { [weak self] app in
            guard let self else { return }
            self.hideLauncher()
            DispatchQueue.main.async {
                NSWorkspace.shared.openApplication(
                    at: app.url,
                    configuration: NSWorkspace.OpenConfiguration(),
                    completionHandler: nil
                )
            }
        }
        viewModel.load()

        textServiceProvider.onProcessText = { [weak self] text in
            self?.presentTextActions(for: text)
        }
        NSApp.servicesProvider = textServiceProvider

        setupStatusItem()
        let initial = settingsStore.load()
        dockIconService.start(style: initial.dockIconStyle)
        apply(settings: initial)
        observeSystemPowerState()
        setupOutsideClickDismissMonitor()
    }

    private func configureAuthenticatorService(_ service: AuthenticatorService) {
        service.onCopyCode = { [weak self] code in
            self?.clipboardStore.writePrivateTextToPasteboard(code)
        }
        service.onSensitiveTextUsed = { [weak self] value in
            self?.clipboardStore.removePrivateTextFromHistory(value)
        }
        service.onICloudSyncPreferenceRejected = { [weak self] in
            guard let self, self.viewModel.settings.authenticatorICloudSyncEnabled else { return }
            self.viewModel.settings.authenticatorICloudSyncEnabled = false
        }
    }

    private func configureCaptureStore(_ store: CaptureStore) {
        store.onArtifactsRemoved = { [weak self] ids in
            guard let self else { return }
            clipboardStore.removeCaptureEntries(ids: ids)
            viewModel.refresh()
        }
    }

    private func configureRecordingService(_ service: RecordingService) {
        service.onCompleted = { [weak self] artifact in
            self?.restoreWhiteboardAfterRecording()
            self?.hideRecordingControl()
            self?.cameraOverlayController.stop()
            self?.screenMagnifierController.stop()
            self?.recordingCoordinator.resetVisualOverlays()
            self?.recordingNotificationService.notifyCompleted(artifact)
            if self?.viewModel.settings.recording.showPreview == true {
                self?.recordingCoordinator.showRecordingPreview(artifact)
            }
        }
        service.onError = { [weak self] error in
            self?.restoreWhiteboardAfterRecording()
            self?.hideRecordingControl()
            self?.cameraOverlayController.stop()
            self?.screenMagnifierController.stop()
            self?.recordingCoordinator.resetVisualOverlays()
            self?.presentRecordingError(error)
        }
        service.onStateChanged = { [weak self] state, elapsed in
            self?.statusItemService.updateRecordingState(state, elapsed: elapsed)
            if case .idle = state {
                self?.restoreWhiteboardAfterRecording()
            } else if case .failed = state {
                self?.restoreWhiteboardAfterRecording()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        lifecycleCoordinator.applicationWillTerminate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lifecycleCoordinator.applicationShouldTerminate(sender)
    }

    func applicationDidBecomeActive(_: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }

    private func observeSystemPowerState() {
        lifecycleCoordinator.observeSystemPowerState()
    }

    private func refreshDateUIAfterWake() {
        dockIconService.refresh()
        statusItemService.refreshDateIcon()

        calendarRefreshToken = UUID()
        windowCoordinator.refreshCalendar { popover in
            self.makeCalendarPopoverView(for: popover)
        }
    }

    private func setupStatusItem() {
        statusItemService.setup(
            initialSettings: viewModel.settings,
            toggleLauncher: { [weak self] in
                self?.toggleLauncher()
            },
            openPreferences: { [weak self] in
                self?.showPreferences()
            },
            showCalendar: { [weak self] in
                self?.showCalendarPopover()
            },
            toggleAutoLaunch: { [weak self] in
                guard let self else { return }
                self.viewModel.settings.autoLaunch.toggle()
            },
            toggleWhiteboard: { [weak self] in
                self?.whiteboardFeatureController.toggleEditing()
            },
            pauseRecording: { [weak self] in
                self?.recordingCoordinator.pauseOrResume()
            },
            stopRecording: { [weak self] in
                self?.recordingCoordinator.stop()
            },
            uploadDroppedFile: { [weak self] url in
                guard self?.viewModel.settings.fileHosting.s3.isEnabled == true else { return }
                self?.upload(fileURL: url)
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    }

    private func apply(settings: AppSettings) {
        var settings = settings
        #if MEOW_VOICE
        let normalizedTTSSettings = settings.tts.normalized()
        if settings.tts != normalizedTTSSettings {
            settings.tts = normalizedTTSSettings
            viewModel.settings.tts = normalizedTTSSettings
        }
        #endif
        let languageChanged = appliedLanguage != settings.language
        if languageChanged {
            LanguageManager.shared.apply(settings.language)
            statusItemService.updateL10n()
            dockIconService.refresh()
            if systemMonitorServiceLoaded {
                systemMonitorService.refreshLocalization()
            }
            viewModel?.refresh()
            windowCoordinator.updatePreferencesTitle(L10n.windowPrefsTitle)
            appliedLanguage = settings.language
        }

        dockService.apply(showDockIcon: settings.showDockIcon)
        dockIconService.apply(style: settings.dockIconStyle)
        statusItemService.setVisible(settings.showStatusItem)
        statusItemService.updateToggleStates(settings)
        statusItemService.updateDateIconStyle(settings.dateIconStyle)
        if settings.fileHosting.s3.isEnabled, !uploadNotificationAuthorizationRequested {
            uploadNotificationAuthorizationRequested = true
            FileUploadNotifications.requestAuthorization()
        }
        if aiChatHistoryStoreLoaded {
            aiChatHistoryStore.setPersistenceEnabled(settings.ai.chatHistoryEnabled)
        }
        if captureStoreLoaded {
            captureStore.applyRetention(
                historyLimit: settings.screenshot.historyLimit,
                retentionDays: settings.screenshot.retentionDays,
                maxStorageMB: settings.screenshot.maxStorageMB
            )
        }
        if recordingServiceLoaded {
            recordingService.apply(settings: settings)
        }
        if recordingStateShowsControls {
            if settings.recording.showFloatingControls {
                showRecordingControl()
            } else {
                hideRecordingControl()
            }
        } else {
            hideRecordingControl()
        }
        if settings.authenticatorEnabled || authenticatorServiceLoaded {
            authenticatorService.apply(
                enabled: settings.authenticatorEnabled,
                iCloudSyncEnabled: settings.authenticatorICloudSyncEnabled,
                theme: settings.theme
            )
        }
        if settings.systemMonitor.enabled || systemMonitorServiceLoaded {
            systemMonitorService.apply(settings: settings.systemMonitor, theme: settings.theme)
        }
        keystrokeVisualizerService.apply(settings: settings)
        healthReminderService.apply(settings: settings)
        keepAwakeService.apply(settings: settings.keepAwake)
        #if MEOW_VOICE
        if settings.speech.enabled || speechRecognitionServiceLoaded {
            speechModelStore.apply(selectedModel: settings.speech.model)
            speechRecognitionService.apply(settings: settings.speech)
        }
        if normalizedTTSSettings.enabled || speechSynthesisServiceLoaded {
            ttsModelStore.apply(selectedModel: normalizedTTSSettings.model)
            speechSynthesisService.apply(settings: normalizedTTSSettings)
        }
        #endif
        let actualAutoLaunchEnabled = autoLaunchService.apply(enabled: settings.autoLaunch)
        hotkeyCoordinator.apply(settings: settings, actions: makeHotkeyActions())
        applyWhiteboard(settings.whiteboard)

        clipboardStore.configure(
            retention: settings.clipboardRetention,
            imageStorageLimitMB: settings.clipboardImageStorageLimitMB,
            disabledAppBundleIDs: settings.clipboardDisabledAppBundleIDs
        )

        if settings.clipboardHistoryEnabled != clipboardMonitoringEnabled {
            if settings.clipboardHistoryEnabled {
                clipboardStore.startMonitoring { [weak self] in
                    self?.viewModel.refresh()
                }
            } else {
                clipboardStore.stopMonitoring()
            }
            clipboardMonitoringEnabled = settings.clipboardHistoryEnabled
            viewModel.refresh()
        }

        if actualAutoLaunchEnabled != settings.autoLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewModel.settings.autoLaunch != actualAutoLaunchEnabled else { return }
                self.viewModel.settings.autoLaunch = actualAutoLaunchEnabled
            }
        }
    }

    private func makeCaptureActions() -> AppCaptureCoordinator.Actions {
        AppCaptureCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            hideTransientPanels: { [weak self] in
                self?.hideLauncher()
                self?.hideTranslationPanel()
            },
            prepareWhiteboard: { [weak self] in
                self?.prepareWhiteboardForCapture() ?? []
            },
            restoreWhiteboard: { [weak self] in
                self?.whiteboardFeatureController.restoreAfterScreenCapture()
            },
            upload: { [weak self] url in
                guard let self else { throw CancellationError() }
                _ = try await self.fileUploadService.upload(fileURL: url)
            },
            refreshLauncher: { [weak self] in
                self?.viewModel.refresh()
            },
            presentScreenshotError: { [weak self] error in
                self?.presentScreenshotError(error)
            },
            presentUploadError: { [weak self] error in
                self?.presentUploadError(error)
            },
            presentScrollingAccessibilityPrompt: { [weak self] in
                self?.presentScrollingCaptureAccessibilityPrompt()
            },
            presentScrollingReducedImageWarning: { [weak self] in
                self?.presentScrollingCaptureReducedImageWarning()
            },
            editImage: { [weak self] url in
                self?.editImage(at: url)
            },
            recognizeClipboardImage: { [weak self] image, translate in
                self?.recognizeClipboardImage(image, translate: translate)
            },
            scanClipboardImageQRCode: { [weak self] image in
                self?.scanClipboardImageQRCode(image)
            },
            askAI: { [weak self] url in
                self?.viewModel.openAIChat(
                    prompt: L10n.aiImagePrompt,
                    imagePath: url.path
                )
            },
            sendImageFileToWhiteboard: { [weak self] url, sourceName in
                self?.sendImageFileToWhiteboard(at: url, sourceName: sourceName)
            }
        )
    }

    private func makeLifecycleActions() -> AppLifecycleCoordinator.Actions {
        AppLifecycleCoordinator.Actions(
            systemDidWake: { [weak self] in
                guard let self else { return }
                self.keepAwakeService.systemDidWake()
                self.refreshDateUIAfterWake()
            },
            systemWillSleep: { [weak self] in
                self?.keepAwakeService.systemWillSleep()
            },
            retryPermissions: { [weak self] in
                self?.keystrokeVisualizerService.retryAfterPermissionChange()
            },
            refreshSpeechPermission: { [weak self] in
                #if MEOW_VOICE
                guard let self,
                      self.speechRecognitionServiceLoaded || self.viewModel.settings.speech.enabled
                else { return }
                self.speechRecognitionService.refreshPermissionState()
                #endif
            },
            shutdownWhiteboard: { [weak self] in
                self?.whiteboardFeatureController.shutdown()
            },
            unregisterHotkeys: { [weak self] in
                self?.hotkeyCoordinator.unregister()
            },
            cancelUpload: { [weak self] in
                self?.fileUploadService.cancel()
            },
            captureCoordinatorLoaded: { [weak self] in
                self?.captureCoordinatorLoaded == true
            },
            cancelCapture: { [weak self] in
                self?.captureCoordinator.cancel()
            },
            recordingServiceLoaded: { [weak self] in
                self?.recordingServiceLoaded == true
            },
            cancelRecording: { [weak self] in
                self?.recordingCoordinator.cancel()
            },
            recordingServiceIsActive: { [weak self] in
                self?.recordingService.state.isActive == true
            },
            stopRecording: { [weak self] in
                await self?.recordingService.stop()
            },
            stopCameraOverlay: { [weak self] in
                self?.cameraOverlayController.stop()
            },
            stopMagnifier: { [weak self] in
                self?.screenMagnifierController.stop()
            },
            cancelCaptureOverlay: { [weak self] in
                self?.captureOverlayController.cancel()
            },
            cancelCaptureEditor: { [weak self] in
                self?.captureEditorController.cancel()
            },
            closePostCaptureActions: { [weak self] in
                self?.postCaptureActionsController.close()
            },
            closePinnedImages: { [weak self] in
                self?.pinnedImageController.closeAll()
            },
            speechRecognitionServiceLoaded: { [weak self] in
                #if MEOW_VOICE
                self?.speechRecognitionServiceLoaded == true
                #else
                false
                #endif
            },
            cancelSpeechRecognition: { [weak self] in
                #if MEOW_VOICE
                self?.speechRecognitionService.cancel()
                #endif
            },
            speechSynthesisServiceLoaded: { [weak self] in
                #if MEOW_VOICE
                self?.speechSynthesisServiceLoaded == true
                #else
                false
                #endif
            },
            cancelSpeechSynthesis: { [weak self] in
                #if MEOW_VOICE
                self?.speechSynthesisService.cancel()
                #endif
            },
            hideSpeechOverlay: { [weak self] in
                #if MEOW_VOICE
                self?.speechOverlayController.hide()
                #endif
            },
            stopKeystrokeVisualizer: { [weak self] in
                self?.keystrokeVisualizerService.stop()
            },
            systemMonitorServiceLoaded: { [weak self] in
                self?.systemMonitorServiceLoaded == true
            },
            stopSystemMonitor: { [weak self] in
                self?.systemMonitorService.stop()
            },
            stopHealthReminder: { [weak self] in
                self?.healthReminderService.stop()
            },
            stopKeepAwake: { [weak self] in
                await self?.keepAwakeService.stop()
            },
            stopClipboardMonitoring: { [weak self] in
                self?.clipboardStore.stopMonitoring()
            },
            stopDockIcon: { [weak self] in
                self?.dockIconService.stop()
            },
            removeEventMonitors: { [weak self] in
                self?.removeEventMonitors()
            },
            shutdownUploads: { [weak self] in
                await self?.fileUploadService.shutdown()
            }
        )
    }

    private func makeRecordingActions() -> AppRecordingCoordinator.Actions {
        AppRecordingCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            captureIsBusy: { [weak self] in self?.captureIsBusy ?? false },
            hideTransientPanels: { [weak self] in
                self?.hideLauncher()
                self?.hideTranslationPanel()
            },
            prepareWhiteboard: { [weak self] in
                self?.prepareWhiteboardForRecording() ?? []
            },
            restoreWhiteboard: { [weak self] in
                self?.restoreWhiteboardAfterRecording()
            },
            activeScreen: { [weak self] in
                self?.activeScreen()
            },
            setSystemAudioMode: { [weak self] in
                self?.viewModel.settings.recording.audioMode = .system
            },
            presentError: { [weak self] error in
                self?.presentRecordingError(error)
            }
        )
    }

    private func makeClipboardActions() -> AppClipboardActionCoordinator.Actions {
        AppClipboardActionCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            hideLauncher: { [weak self] in
                self?.hideLauncher()
            },
            presentTranslation: { [weak self] text, axPermissionDenied, sourceImagePath in
                self?.presentTranslationPanel(
                    text: text,
                    axPermissionDenied: axPermissionDenied,
                    sourceImagePath: sourceImagePath
                )
            },
            presentScreenshotError: { [weak self] error in
                self?.presentScreenshotError(error)
            },
            presentUploadError: { [weak self] error in
                self?.presentUploadError(error)
            },
            importImageFileToWhiteboard: { [weak self] url, sourceName in
                self?.sendImageFileToWhiteboard(at: url, sourceName: sourceName)
            },
            onArtifactReady: { [weak self] artifact in
                self?.captureCoordinator.showPostCaptureActionsIfNeeded(for: artifact)
            },
            presentOTPAuthImport: { [weak self] payload in
                self?.presentOTPAuthImport(payload)
            },
            presentQRCodePayload: { [weak self] payload in
                self?.presentQRCodePayload(payload)
            }
        )
    }

    private func makeTextActions() -> AppTextActionCoordinator.Actions {
        #if MEOW_VOICE
        return AppTextActionCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            openAIChat: { [weak self] input in
                self?.openAIChat(input)
            },
            speak: { [weak self] text in
                guard let self else { return }
                self.speechSynthesisService.synthesize(
                    text: text,
                    settings: self.viewModel.settings.tts
                )
            }
        )
        #else
        return AppTextActionCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            openAIChat: { [weak self] input in
                self?.openAIChat(input)
            }
        )
        #endif
    }

    private func makeHotkeyActions() -> AppHotkeyCoordinator.Actions {
        AppHotkeyCoordinator.Actions(
            invoke: { [weak self] event in
                self?.handleHotkeyEvent(event)
            },
            restore: { [weak self] kind, keyCode, modifiers in
                self?.restoreHotkey(kind, keyCode: keyCode, modifiers: modifiers)
            },
            registrationSucceeded: { [weak self] kind in
                self?.handleHotkeyRegistrationSuccess(kind)
            },
            registrationFailure: { [weak self] kind, status in
                self?.handleHotkeyRegistrationFailure(kind, status: status)
            }
        )
    }

    private func handleHotkeyEvent(_ event: AppHotkeyCoordinator.Event) {
        switch event {
        case .toggleLauncher:
            toggleLauncher()
        case .openFinder:
            openFinder()
        case .translate:
            triggerTranslation()
        case .textActions:
            triggerTextActions()
        case .screenshotDefault:
            triggerScreenshot(mode: viewModel.settings.screenshot.defaultCaptureMode)
        case .screenshotDefaultAndEdit:
            triggerScreenshot(
                mode: viewModel.settings.screenshot.defaultCaptureMode,
                editAfterCapture: true
            )
        case .scrollingScreenshot:
            triggerScrollingCapture()
        case let .screenshot(mode):
            triggerScreenshot(mode: mode)
        case let .recording(mode):
            triggerRecording(mode: mode)
        case .pauseRecording:
            recordingService.pauseOrResume()
        case .stopRecording:
            Task { await recordingService.stop() }
        case .saveRecordingFrame:
            saveRecordingFrame()
        case .toggleRecordingMagnifier:
            toggleRecordingMagnifier()
        case .uploadScreenshot:
            triggerScreenshot(mode: .region, uploadAfterCapture: true)
        case .toggleWhiteboard:
            whiteboardFeatureController.toggleEditing()
        #if MEOW_VOICE
        case .speechPressed:
            speechRecognitionService.hotkeyPressed()
        case .speechReleased:
            speechRecognitionService.hotkeyReleased()
        case .speakSelectedText:
            speakSelectedTextViaHotkey()
        #endif
        }
    }

    private func restoreHotkey(
        _ kind: AppHotkeyCoordinator.Kind,
        keyCode: UInt32,
        modifiers: UInt32
    ) {
        switch kind {
        case .launcher:
            viewModel.updateLauncherHotkey(keyCode: keyCode, modifiers: modifiers)
        case .finder:
            viewModel.updateFinderHotkey(keyCode: keyCode, modifiers: modifiers)
        case .translation:
            viewModel.updateTranslateHotkey(keyCode: keyCode, modifiers: modifiers)
        case .textActions:
            viewModel.updateTextActionsHotkey(keyCode: keyCode, modifiers: modifiers)
        case .screenshotRegion:
            viewModel.settings.screenshot.regionHotkeyKeyCode = keyCode
            viewModel.settings.screenshot.regionHotkeyModifiers = modifiers
        case .screenshotScrolling:
            viewModel.settings.screenshot.scrollingHotkeyKeyCode = keyCode
            viewModel.settings.screenshot.scrollingHotkeyModifiers = modifiers
        case .screenshotEdit:
            viewModel.settings.screenshot.editHotkeyKeyCode = keyCode
            viewModel.settings.screenshot.editHotkeyModifiers = modifiers
        case .screenshotWindow:
            viewModel.settings.screenshot.windowHotkeyKeyCode = keyCode
            viewModel.settings.screenshot.windowHotkeyModifiers = modifiers
        case .screenshotDisplay:
            viewModel.settings.screenshot.displayHotkeyKeyCode = keyCode
            viewModel.settings.screenshot.displayHotkeyModifiers = modifiers
        case .recordingDisplay:
            viewModel.settings.recording.displayHotkeyKeyCode = keyCode
            viewModel.settings.recording.displayHotkeyModifiers = modifiers
        case .recordingRegion:
            viewModel.settings.recording.regionHotkeyKeyCode = keyCode
            viewModel.settings.recording.regionHotkeyModifiers = modifiers
        case .recordingWindow:
            viewModel.settings.recording.windowHotkeyKeyCode = keyCode
            viewModel.settings.recording.windowHotkeyModifiers = modifiers
        case .recordingPause:
            viewModel.settings.recording.pauseHotkeyKeyCode = keyCode
            viewModel.settings.recording.pauseHotkeyModifiers = modifiers
        case .recordingStop:
            viewModel.settings.recording.stopHotkeyKeyCode = keyCode
            viewModel.settings.recording.stopHotkeyModifiers = modifiers
        case .recordingFrame:
            viewModel.settings.recording.frameHotkeyKeyCode = keyCode
            viewModel.settings.recording.frameHotkeyModifiers = modifiers
        case .recordingMagnifier:
            viewModel.settings.recording.magnifierHotkeyKeyCode = keyCode
            viewModel.settings.recording.magnifierHotkeyModifiers = modifiers
        case .upload:
            viewModel.settings.fileHosting.uploadHotkeyKeyCode = keyCode
            viewModel.settings.fileHosting.uploadHotkeyModifiers = modifiers
        case .whiteboard:
            viewModel.settings.whiteboard.hotkeyKeyCode = keyCode
            viewModel.settings.whiteboard.hotkeyModifiers = modifiers
        #if MEOW_VOICE
        case .speech:
            viewModel.settings.speech.hotkeyKeyCode = keyCode
            viewModel.settings.speech.hotkeyModifiers = modifiers
        case .textToSpeech:
            viewModel.settings.ttsHotkeyKeyCode = keyCode
            viewModel.settings.ttsHotkeyModifiers = modifiers
        #endif
        }
    }

    private func handleHotkeyRegistrationSuccess(_ kind: AppHotkeyCoordinator.Kind) {
        switch kind {
        case .finder:
            viewModel.setFinderHotkeyRegistrationError(nil)
        case .whiteboard:
            viewModel.setWhiteboardHotkeyRegistrationError(nil)
        default:
            break
        }
    }

    private func handleHotkeyRegistrationFailure(
        _ kind: AppHotkeyCoordinator.Kind,
        status: OSStatus
    ) {
        switch kind {
        case .finder:
            viewModel.setFinderHotkeyRegistrationError(
                String(format: L10n.prefsFinderHotkeyError, status)
            )
        case .textActions:
            presentTextActionsHotkeyConflict(
                keyCode: viewModel.settings.textActionsHotkeyKeyCode,
                modifiers: viewModel.settings.textActionsHotkeyModifiers
            )
        case .whiteboard:
            viewModel.setWhiteboardHotkeyRegistrationError(
                String(format: L10n.whiteboardHotkeyError, status)
            )
        default:
            break
        }
    }

    private func handleHealthCommand(_ command: HealthReminderCommand) {
        switch command {
        case .start:
            if !viewModel.settings.healthReminder.enabled {
                viewModel.settings.healthReminder.enabled = true
            }
            healthReminderService.startWorking()
        case .pauseResume:
            if !viewModel.settings.healthReminder.enabled {
                viewModel.settings.healthReminder.enabled = true
                return
            }
            healthReminderService.pauseOrResume()
        case .startBreak:
            if !viewModel.settings.healthReminder.enabled {
                viewModel.settings.healthReminder.enabled = true
            }
            healthReminderService.startBreak()
        case .skipBreak:
            guard viewModel.settings.healthReminder.enabled else { return }
            healthReminderService.skipBreak()
        }
    }

    private func handleKeepAwakeCommand() {
        hideLauncher()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await keepAwakeService.toggle()
            } catch is CancellationError {
                // An in-flight start can be invalidated by a user stop or replacement.
            } catch {
                presentKeepAwakeError(error)
            }
        }
    }

    private func applyWhiteboard(_ settings: WhiteboardSettings) {
        let normalized = settings.normalized()
        whiteboardFeatureController.apply(
            configuration: WhiteboardConfiguration(
                isEnabled: normalized.enabled,
                idleVisibility: normalized.idleVisibility,
                includeInCaptures: normalized.includeInCaptures,
                surfaceStyle: normalized.surfaceStyle,
                guideStyle: normalized.guideStyle,
                outputBackgroundStyle: normalized.outputBackgroundStyle,
                editOpacity: normalized.editOpacity,
                storageDirectory: whiteboardStorageDirectory,
                languageCode: LanguageManager.shared.currentLanguageCode,
                applicationName: BuildEdition.productName
            )
        )

        guard normalized.enabled else {
            if whiteboardPreparedForRecording {
                recordingService.setIncludedApplicationWindowIDs([])
                whiteboardPreparedForRecording = false
            }
            viewModel.setWhiteboardHotkeyRegistrationError(nil)
            return
        }
    }

    private var whiteboardStorageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(BuildEdition.productName, isDirectory: true)
            .appendingPathComponent("Whiteboards", isDirectory: true)
    }

    private func handleWhiteboardCommand(_ command: WhiteboardCommand) {
        guard viewModel.settings.whiteboard.enabled else { return }
        hideLauncher()
        switch command {
        case .show:
            whiteboardFeatureController.showBoard()
        case .toggleEditing:
            whiteboardFeatureController.toggleEditing()
        case .importLatestScreenshot:
            guard let artifact = captureStore.artifacts.first else {
                presentWhiteboardError(L10n.whiteboardNoRecentScreenshot)
                return
            }
            sendImageFileToWhiteboard(
                at: artifact.imageURL,
                sourceName: artifact.imageURL.lastPathComponent
            )
        }
    }

    private func sendImageToWhiteboard(_ image: ImageClipboardContent) {
        clipboardActionCoordinator.sendImageToWhiteboard(image)
    }

    private func sendImageFileToWhiteboard(at url: URL, sourceName: String?) {
        guard viewModel.settings.whiteboard.enabled,
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            presentWhiteboardError(L10n.screenshotErrorCaptureFailed)
            return
        }
        whiteboardFeatureController.importImage(cgImage, sourceName: sourceName)
    }

    private func prepareWhiteboardForCapture() -> Set<CGWindowID> {
        guard viewModel.settings.whiteboard.enabled else { return [] }
        let includeContent = viewModel.settings.whiteboard.includeInCaptures
        whiteboardFeatureController.prepareForScreenCapture(
            includeContent ? .includeContent : .excludeContent
        )
        guard includeContent, let windowID = whiteboardFeatureController.captureWindowNumber else {
            return []
        }
        return [windowID]
    }

    private func prepareWhiteboardForRecording() -> Set<CGWindowID> {
        guard !whiteboardPreparedForRecording else {
            if let windowID = whiteboardFeatureController.captureWindowNumber,
               viewModel.settings.whiteboard.includeInCaptures
            {
                return [windowID]
            }
            return []
        }
        let windowIDs = prepareWhiteboardForCapture()
        whiteboardPreparedForRecording = viewModel.settings.whiteboard.enabled
        recordingService.setIncludedApplicationWindowIDs(windowIDs)
        return windowIDs
    }

    private func restoreWhiteboardAfterRecording() {
        guard whiteboardPreparedForRecording else { return }
        recordingService.setIncludedApplicationWindowIDs([])
        whiteboardFeatureController.restoreAfterScreenCapture()
        whiteboardPreparedForRecording = false
    }

    private func presentWhiteboardError(_ message: String) {
        guard viewModel?.settings.whiteboard.enabled == true else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.whiteboardErrorTitle
        alert.informativeText = message
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func handleScreenshotCommand(_ command: ScreenshotCommand) {
        switch command {
        case .captureRegion:
            triggerScreenshot(mode: .region)
        case .captureScrolling:
            triggerScrollingCapture()
        case .captureAndEdit:
            triggerScreenshot(
                mode: viewModel.settings.screenshot.defaultCaptureMode,
                editAfterCapture: true
            )
        case .captureWindow:
            triggerScreenshot(mode: .window)
        case .captureDisplay:
            triggerScreenshot(mode: .display)
        case .openHistory:
            showCaptureHistory()
        }
    }

    private func handleRecordingCommand(_ command: RecordingCommand) {
        switch command {
        case .recordDisplay:
            triggerRecording(mode: .display)
        case .recordRegion:
            triggerRecording(mode: .region)
        case .recordWindow:
            triggerRecording(mode: .window)
        case .recordWindows:
            triggerMultipleWindowRecording()
        case .recordApplication:
            triggerApplicationRecording()
        case .recordSystemAudio:
            triggerSystemAudioRecording()
        case .recordMobileDevice:
            triggerMobileDeviceRecording()
        case .pauseResume:
            recordingCoordinator.pauseOrResume()
        case .stop:
            recordingCoordinator.stop()
        case .saveCurrentFrame:
            saveRecordingFrame()
        case .toggleMagnifier:
            toggleRecordingMagnifier()
        case .openHistory:
            showRecordingHistory()
        }
    }

    private func triggerRecording(mode: ScreenshotCaptureMode) {
        recordingCoordinator.triggerRecording(mode: mode)
    }

    private func triggerApplicationRecording() {
        recordingCoordinator.triggerApplicationRecording()
    }

    private func triggerMultipleWindowRecording() {
        recordingCoordinator.triggerMultipleWindowRecording()
    }

    private func triggerSystemAudioRecording() {
        recordingCoordinator.triggerSystemAudioRecording()
    }

    private func triggerMobileDeviceRecording() {
        recordingCoordinator.triggerMobileDeviceRecording()
    }

    private func toggleRecordingMagnifier() {
        recordingCoordinator.toggleMagnifier()
    }

    private func saveRecordingFrame() {
        recordingCoordinator.saveCurrentFrame()
    }



    private var recordingStateShowsControls: Bool {
        guard recordingServiceLoaded else { return false }
        return recordingCoordinator.recordingStateShowsControls
    }

    private func showRecordingControl() {
        recordingCoordinator.showRecordingControl()
    }

    private func hideRecordingControl() {
        recordingCoordinator.hideRecordingControl()
    }

    private func showRecordingPreview(_ artifact: RecordingArtifact) {
        recordingCoordinator.showRecordingPreview(artifact)
    }

    private func showRecordingHistory() {
        recordingCoordinator.showRecordingHistory()
    }

    private func showRecordingTrimmer(for url: URL) {
        recordingCoordinator.showRecordingTrimmer(for: url)
    }

    private func presentRecordingError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.recordingErrorTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.actionOK)
        if case .permissionDenied? = error as? RecordingError {
            alert.addButton(withTitle: L10n.screenshotOpenSettings)
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func triggerScreenshot(
        mode: ScreenshotCaptureMode,
        editAfterCapture: Bool = false,
        uploadAfterCapture: Bool = false
    ) {
        captureCoordinator.triggerScreenshot(
            mode: mode,
            editAfterCapture: editAfterCapture,
            uploadAfterCapture: uploadAfterCapture
        )
    }



    private func triggerScrollingCapture() {
        captureCoordinator.triggerScrollingCapture()
    }



    private func presentScrollingCaptureAccessibilityPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.scrollingCaptureAccessibilityTitle
        alert.informativeText = L10n.scrollingCaptureAccessibilityMessage
        alert.addButton(withTitle: L10n.screenshotOpenSettings)
        alert.addButton(withTitle: L10n.actionCancel)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(
               string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
           )
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentScrollingCaptureReducedImageWarning() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.scrollingCaptureReducedImageTitle
        alert.informativeText = L10n.scrollingCaptureReducedImageMessage
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func presentScreenshotError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.screenshotErrorTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.actionOK)
        if case .permissionDenied? = error as? ScreenCaptureError {
            alert.addButton(withTitle: L10n.screenshotOpenSettings)
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func showCaptureHistory() {
        hideLauncher()
        captureCoordinator.showCaptureHistory()
    }

    private func makeCaptureHistoryView(theme: AppTheme) -> CaptureHistoryView {
        captureCoordinator.makeCaptureHistoryView(theme: theme)
    }

    private func showLauncher() {
        viewModel.updateKeepAwakeState(
            keepAwakeService.state,
            remainingMinutes: keepAwakeService.remainingMinutes
        )
        // Keep app list fresh so newly installed apps appear without restarting Meow.
        if !viewModel.refreshInstalledApps() {
            viewModel.refresh()
        }
        #if MEOW_VOICE
        if viewModel.settings.tts.enabled {
            selectedTextForTts = translationService.captureViaAccessibility()
            ttsSelectionPermissionDenied = translationService.axPermissionDenied
        } else {
            selectedTextForTts = ""
            ttsSelectionPermissionDenied = false
        }
        #endif
        windowCoordinator.showLauncher { [weak self] in
            guard let self else { return NSViewController() }
            return NSHostingController(
                rootView: LauncherView(viewModel: self.viewModel) { [weak self] in
                    self?.hideLauncher()
                }
            )
        }
    }

    #if MEOW_VOICE
    private func speakCapturedSelection() {
        let text = selectedTextForTts
        let permissionDenied = ttsSelectionPermissionDenied
        hideLauncher()

        if text.isEmpty, !permissionDenied {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                let fallbackText = self.translationService.captureWithFallback(promptForPermission: true)
                self.ttsSelectionPermissionDenied = self.translationService.axPermissionDenied
                self.speakSelectedText(fallbackText)
            }
            return
        }

        speakSelectedText(text)
    }

    private func speakSelectedText(_ text: String) {
        guard !text.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L10n.ttsSelectionUnavailableTitle
            alert.informativeText = ttsSelectionPermissionDenied
                ? L10n.ttsSelectionPermissionMessage
                : L10n.ttsSelectionEmptyMessage
            if ttsSelectionPermissionDenied {
                alert.addButton(withTitle: L10n.translateOpenPrivacy)
                alert.addButton(withTitle: L10n.actionCancel)
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(
                        URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )!
                    )
                }
            } else {
                alert.addButton(withTitle: L10n.actionOK)
                alert.runModal()
            }
            return
        }

        speechSynthesisService.synthesize(text: text, settings: viewModel.settings.tts)
    }

    private func speakSelectedTextViaHotkey() {
        guard viewModel.settings.tts.enabled else { return }
        selectedTextForTts = translationService.captureWithFallback(promptForPermission: true)
        ttsSelectionPermissionDenied = translationService.axPermissionDenied
        speakCapturedSelection()
    }
    #endif

    private func hideLauncher() {
        windowCoordinator.hideLauncher()
        viewModel.resetForHide()
        NotificationCenter.default.post(name: .meowLauncherDidHide, object: nil)
    }

    private func toggleLauncher() {
        if windowCoordinator.isLauncherVisible {
            hideLauncher()
        } else {
            showLauncher()
        }
    }

    private func openFinder() {
        hideLauncher()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        guard NSWorkspace.shared.open(homeDirectory) else {
            NSLog("[Meow] Failed to open Finder at %@", homeDirectory.path)
            return
        }
    }

    /// Simulates Cmd+V to paste the clipboard content into the frontmost app.
    private func simulatePaste() {
        // Check accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        guard trusted else {
            // If not trusted, the system will show a prompt for permission
            // Try anyway - if the user approved in the prompt, it might work
            NSLog("[Meow] Accessibility permission not granted, paste may not work")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) // V key
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func setupOutsideClickDismissMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            self?.dismissIfClickedOutsideLauncher()
            self?.dismissIfClickedOutsideTranslation()
            self?.dismissIfClickedOutsideTextActions()
            self?.dismissIfClickedOutsideCalendarPopover()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            self?.dismissIfClickedOutsideLauncher()
            self?.dismissIfClickedOutsideTranslation()
            self?.dismissIfClickedOutsideTextActions()
            self?.dismissIfClickedOutsideCalendarPopover()
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            #if MEOW_VOICE
            if event.keyCode == 53,
               self?.speechRecognitionServiceLoaded == true,
               self?.speechRecognitionService.state.isActive == true
            {
                self?.speechRecognitionService.cancel()
            }
            #endif
            self?.dismissTranslationIfEscape(event)
            self?.dismissTextActionsIfEscape(event)
        }

        // Use a single app-level shortcut path for Cmd+, because command routing can
        // be unreliable when the launcher is a nonactivating panel.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                var handled = false
                #if MEOW_VOICE
                if self?.speechRecognitionServiceLoaded == true,
                   self?.speechRecognitionService.state.isActive == true
                {
                    self?.speechRecognitionService.cancel()
                    handled = true
                }
                #endif
                if self?.dismissTranslationIfEscape(event) == true {
                    handled = true
                }
                if self?.dismissTextActionsIfEscape(event) == true {
                    handled = true
                }
                if handled {
                    return nil
                }
            }
            if self?.dismissTranslationIfEscape(event) == true {
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command), event.charactersIgnoringModifiers == "," {
                self?.showPreferences(animated: true)
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func dismissIfClickedOutsideLauncher() {
        guard windowCoordinator.isLauncherVisible,
              let launcherFrame = windowCoordinator.launcherFrame()
        else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !launcherFrame.contains(mouseLocation) {
            hideLauncher()
        }
    }

    private func dismissIfClickedOutsideTranslation() {
        guard windowCoordinator.isTranslationVisible,
              let translationFrame = windowCoordinator.translationFrame()
        else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !translationFrame.contains(mouseLocation) {
            hideTranslationPanel()
        }
    }

    private func dismissIfClickedOutsideTextActions() {
        guard windowCoordinator.isTextActionsVisible,
              let textActionsFrame = windowCoordinator.textActionsFrame()
        else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !textActionsFrame.contains(mouseLocation) {
            hideTextActionsPanel()
        }
    }

    private func dismissIfClickedOutsideCalendarPopover() {
        guard windowCoordinator.isCalendarPopoverShown else { return }
        let mouseLocation = NSEvent.mouseLocation
        if windowCoordinator.calendarPopoverContains(
            mouseLocation: mouseLocation,
            statusButton: statusItemService.statusItemButton
        ) {
            return
        }
        windowCoordinator.dismissCalendarPopover()
    }

    @discardableResult
    private func dismissTranslationIfEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              windowCoordinator.isTranslationVisible
        else { return false }

        hideTranslationPanel()
        return true
    }

    @discardableResult
    private func dismissTextActionsIfEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              windowCoordinator.isTextActionsVisible
        else { return false }

        hideTextActionsPanel()
        return true
    }

    // MARK: - Translation panel

    private func presentTextActionsHotkeyConflict(keyCode: UInt32, modifiers: UInt32) {
        textActionCoordinator.presentTextActionsHotkeyConflict(
            keyCode: keyCode,
            modifiers: modifiers
        )
    }

    private func triggerTextActions() {
        textActionCoordinator.triggerTextActions()
    }

    private func presentTextActions(for text: String) {
        textActionCoordinator.presentTextActions(for: text)
    }

    private func hideTextActionsPanel() {
        textActionCoordinator.hideTextActionsPanel()
    }

    private func showAIChat(initialInput: AIChatInitialInput?) {
        let view = AnyView(
            AIChatPanelView(
                viewModel: viewModel,
                initialInput: initialInput,
                historyStore: aiChatHistoryStore,
                onOpenPreferences: { [weak self] in
                    self?.showPreferences(section: .ai)
                }
            )
        )
        hideLauncher()
        windowCoordinator.showAIChat(contentViewController: NSHostingController(rootView: view))
    }

    private func openAIChat(_ input: AIChatInitialInput?) {
        guard let input, input.imagePath != nil else {
            showAIChat(initialInput: input)
            return
        }
        guard viewModel.settings.ai.supportsVision else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.aiErrorVisionUnsupportedTitle
            alert.informativeText = L10n.aiErrorVisionUnsupported
            alert.addButton(withTitle: L10n.prefsAIModelOpenSettings)
            alert.addButton(withTitle: L10n.actionCancel)
            if alert.runModal() == .alertFirstButtonReturn {
                showPreferences(section: .ai)
            }
            return
        }

        let settings = viewModel.settings.ai
        let alert = NSAlert()
        alert.messageText = L10n.aiImagePrivacyTitle
        alert.informativeText = String(
            format: L10n.aiImagePrivacyMessage,
            settings.endpoint,
            settings.imageMaxDimension,
            Int(settings.imageJPEGQuality * 100)
        )
        alert.addButton(withTitle: L10n.aiImagePrivacyConfirm)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        showAIChat(initialInput: persistedAIInput(input))
    }

    private func persistedAIInput(_ input: AIChatInitialInput?) -> AIChatInitialInput? {
        guard let input, let imagePath = input.imagePath else { return input }
        do {
            let persistedPath = try aiChatHistoryStore.storeAttachment(
                at: URL(fileURLWithPath: imagePath)
            )
            return AIChatInitialInput(text: input.text, imagePath: persistedPath)
        } catch {
            return input
        }
    }

    private func triggerTranslation() {
        textActionCoordinator.triggerTranslation()
    }

    private func presentTranslationPanel(
        text: String,
        axPermissionDenied: Bool,
        sourceImagePath: String? = nil
    ) {
        textActionCoordinator.presentTranslationPanel(
            text: text,
            axPermissionDenied: axPermissionDenied,
            sourceImagePath: sourceImagePath
        )
    }

    private func recognizeClipboardImage(_ image: ImageClipboardContent, translate: Bool) {
        clipboardActionCoordinator.recognizeClipboardImage(image, translate: translate)
    }

    private func scanClipboardImageQRCode(_ image: ImageClipboardContent) {
        clipboardActionCoordinator.scanClipboardImageQRCode(image)
    }

    private func editClipboardImage(_ image: ImageClipboardContent) {
        clipboardActionCoordinator.editClipboardImage(image)
    }

    private func openClipboardImage(_ image: ImageClipboardContent) {
        clipboardActionCoordinator.openClipboardImage(image)
    }

    private func saveClipboardImageAs(_ image: ImageClipboardContent) {
        clipboardActionCoordinator.saveClipboardImageAs(image)
    }

    private func editImage(at url: URL) {
        clipboardActionCoordinator.editImage(at: url)
    }

    private func upload(fileURL: URL) {
        clipboardActionCoordinator.upload(fileURL: fileURL)
    }

    private func uploadFromClipboard() {
        clipboardActionCoordinator.uploadFromClipboard()
    }

    private func presentUploadError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.uploadErrorTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func presentKeepAwakeError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.keepAwakeErrorTitle
        alert.informativeText = String(
            format: L10n.keepAwakeUnavailableMessage,
            error.localizedDescription
        )
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func presentOTPAuthImport(_ payload: String) {
        guard let parsed = OTPAuthURL.parse(payload) else {
            presentScreenshotError(AuthenticatorError.invalidURL)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.screenshotQRImportOTPTitle
        alert.informativeText = String(
            format: L10n.screenshotQRImportOTPMessage,
            parsed.issuer.isEmpty ? "-" : parsed.issuer,
            parsed.account
        )
        alert.addButton(withTitle: L10n.screenshotQRImportOTPConfirm)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if !viewModel.settings.authenticatorEnabled {
                viewModel.settings.authenticatorEnabled = true
            }
            try authenticatorService.importOTPAuth(payload)
            authenticatorService.showPanel()
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = L10n.screenshotQRImportOTPFailed
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: L10n.actionOK)
            failure.runModal()
        }
    }

    private func presentQRCodePayload(_ payload: String) {
        let url = URL(string: payload)
        let canOpen = url.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false

        let alert = NSAlert()
        alert.messageText = L10n.screenshotQRResultTitle
        alert.informativeText = payload
        if canOpen {
            alert.addButton(withTitle: L10n.screenshotQROpen)
        }
        alert.addButton(withTitle: L10n.actionMenuCopy)
        alert.addButton(withTitle: L10n.actionCancel)
        let response = alert.runModal()

        if canOpen, response == .alertFirstButtonReturn, let url {
            NSWorkspace.shared.open(url)
            return
        }

        let copyResponse = canOpen ? NSApplication.ModalResponse.alertSecondButtonReturn : .alertFirstButtonReturn
        if response == copyResponse {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
        }
    }

    private func hideTranslationPanel() {
        windowCoordinator.hideTranslation()
    }

    private func showPreferences(section: PreferenceSection? = nil, animated: Bool = true) {
        hideLauncher()
        preferencesCoordinator.show(section: section, animated: animated)
    }

    func openPreferencesFromCommand() {
        showPreferences(animated: true)
    }

    private func showCalendarPopover() {
        guard let button = statusItemService.statusItemButton else { return }
        windowCoordinator.toggleCalendarPopover(
            contentView: { popover in
                self.makeCalendarPopoverView(for: popover)
            },
            relativeTo: button
        )
    }

    private func makeCalendarPopoverView(for popover: NSPopover? = nil) -> CalendarPopoverView {
        CalendarPopoverView(
            theme: viewModel.settings.theme,
            healthReminderService: healthReminderService,
            onHealthCommand: { [weak self] command in
                self?.handleHealthCommand(command)
            },
            onOpenHealthPreferences: { [weak self] in
                self?.showPreferences(section: .health)
            },
            onContentSizeChanged: { [weak popover] size in
                popover?.contentSize = size
            },
            refreshToken: calendarRefreshToken
        )
    }

    private func activeScreen() -> NSScreen? {
        windowCoordinator.activeScreen()
    }

    private func centerWindowOnScreen(_ window: NSWindow, on targetScreen: NSScreen? = nil) {
        windowCoordinator.center(window, on: targetScreen)
    }
}
