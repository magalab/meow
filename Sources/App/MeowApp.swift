import MeowRecording
import MeowClipboard
import MeowCapture
import AppKit
import MeowAI
import MeowLauncher
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
    private let mediaErrorPresenter = AppMediaErrorPresenter()
    private lazy var authenticatorCoordinator = AppAuthenticatorCoordinator(
        actions: AppAuthenticatorCoordinator.Actions(
            authenticatorEnabled: { [weak self] in self?.viewModel.settings.authenticatorEnabled ?? false },
            enableAuthenticator: { [weak self] in self?.viewModel.settings.authenticatorEnabled = true },
            importOTPAuth: { [weak self] payload in
                guard let self else { throw CancellationError() }
                try self.authenticatorService.importOTPAuth(payload)
            },
            showAuthenticator: { [weak self] in self?.authenticatorService.showPanel() },
            presentInvalidOTPAuth: { [weak self] in
                self?.mediaErrorPresenter.presentScreenshotError(AuthenticatorError.invalidURL)
            }
        )
    )

    private var settingsStore: SettingsStore { serviceRegistry.settingsStore }
    private var dockService: DockService { serviceRegistry.dockService }
    private var dockIconService: DockIconService { serviceRegistry.dockIconService }
    private var statusItemService: StatusItemService { serviceRegistry.statusItemService }
    private var discoveryService: AppDiscoveryService { serviceRegistry.discoveryService }
    private var launchHistoryStore: LaunchHistoryStore { serviceRegistry.launchHistoryStore }
    private var autoLaunchService: AutoLaunchService { serviceRegistry.autoLaunchService }
    private lazy var hotkeyCoordinator = AppHotkeyCoordinator(hotkeyService: HotkeyService())
    private lazy var hotkeyRouter = AppHotkeyRouter(actions: makeHotkeyRouterActions())
    private lazy var mediaCommandRouter = AppMediaCommandRouter(actions: makeMediaCommandRouterActions())
    private lazy var settingsCoordinator = AppSettingsCoordinator(actions: makeSettingsActions())
    private var keystrokeVisualizerService: KeystrokeVisualizerService {
        serviceRegistry.keystrokeVisualizerService
    }
    private var whiteboardFeatureController: WhiteboardFeatureController {
        serviceRegistry.whiteboardFeatureController
    }
    private lazy var whiteboardCoordinator = AppWhiteboardCoordinator(
        controller: whiteboardFeatureController,
        actions: AppWhiteboardCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings.whiteboard ?? .default },
            latestScreenshot: { [weak self] in self?.captureStore.artifacts.first?.imageURL },
            hideLauncher: { [weak self] in self?.launcherCoordinator.hide() },
            setRecordingWindowIDs: { [weak self] in self?.recordingService.setIncludedApplicationWindowIDs($0) }
        )
    )
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
    private lazy var healthReminderCoordinator = AppHealthReminderCoordinator(
        actions: AppHealthReminderCoordinator.Actions(
            isEnabled: { [weak self] in self?.viewModel.settings.healthReminder.enabled ?? false },
            enable: { [weak self] in self?.viewModel.settings.healthReminder.enabled = true },
            startWorking: { [weak self] in self?.healthReminderService.startWorking() },
            pauseOrResume: { [weak self] in self?.healthReminderService.pauseOrResume() },
            startBreak: { [weak self] in self?.healthReminderService.startBreak() },
            skipBreak: { [weak self] in self?.healthReminderService.skipBreak() }
        )
    )
    private lazy var calendarCoordinator = AppCalendarCoordinator(
        windowCoordinator: windowCoordinator,
        healthReminderService: healthReminderService,
        actions: AppCalendarCoordinator.Actions(
            statusItemButton: { [weak self] in self?.statusItemService.statusItemButton },
            theme: { [weak self] in self?.viewModel.settings.theme ?? .gingerCat },
            handleHealthCommand: { [weak self] in self?.healthReminderCoordinator.handle($0) },
            openHealthPreferences: { [weak self] in self?.preferencesCoordinator.show(section: .health) }
        )
    )
    private lazy var keepAwakeCommandCoordinator = AppKeepAwakeCommandCoordinator(
        actions: AppKeepAwakeCommandCoordinator.Actions(
            hideLauncher: { [weak self] in self?.launcherCoordinator.hide() },
            toggleKeepAwake: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.keepAwakeService.toggle()
            },
            presentError: { [weak self] in self?.presentKeepAwakeError($0) }
        )
    )
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
            actions: mediaCommandRouter.makeCaptureActions()
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
        recordingNotificationService: recordingNotificationService,
        cameraOverlayController: cameraOverlayController,
        screenMagnifierController: screenMagnifierController,
        windowCoordinator: windowCoordinator,
        actions: mediaCommandRouter.makeRecordingActions()
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
    private var speechRecognitionServiceLoaded = false
    private lazy var speechRecognitionService: SpeechRecognitionService = {
        speechRecognitionServiceLoaded = true
        let service = SpeechRecognitionService(
            modelStore: speechModelStore,
            historyStore: speechHistoryStore,
            clipboardStore: clipboardStore
        )
        service.onNeedsModel = { [weak self] in
            self?.preferencesCoordinator.show(section: .speech)
        }
        speechOverlayController.connect(to: service)
        service.apply(settings: viewModel.settings.speech)
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
    private lazy var launcherCoordinator = AppLauncherCoordinator(
        viewModel: viewModel,
        keepAwakeService: keepAwakeService,
        windowCoordinator: windowCoordinator
    )
    private lazy var aiChatCoordinator = AppAIChatCoordinator(
        viewModel: viewModel,
        historyStore: aiChatHistoryStore,
        launcherCoordinator: launcherCoordinator,
        windowCoordinator: windowCoordinator,
        actions: AppAIChatCoordinator.Actions(
            showAIPreferences: { [weak self] in self?.preferencesCoordinator.show(section: .ai) }
        )
    )
    private lazy var lifecycleCoordinator = AppLifecycleCoordinator(
        actions: makeLifecycleActions(),
        startupActions: AppLifecycleCoordinator.StartupActions(
            prepareApplication: { [weak self] in self?.prepareApplicationForLaunch() },
            setupStatusItem: { [weak self] in self?.setupStatusItem() },
            applyInitialSettings: { [weak self] in self?.applyInitialSettings() },
            installEventMonitors: { [weak self] in self?.setupOutsideClickDismissMonitor() }
        )
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
                self?.captureCoordinator.makeCaptureHistoryView(theme: theme) ?? CaptureHistoryView(
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
                self?.recordingCoordinator.showRecordingTrimmer(for: url)
            },
            hideLauncher: { [weak self] in self?.launcherCoordinator.hide() },
            speechModelStore: speechModelStore,
            speechHistoryStore: speechHistoryStore,
            speechRecognitionService: speechRecognitionService
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
                self?.captureCoordinator.makeCaptureHistoryView(theme: theme) ?? CaptureHistoryView(
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
                self?.recordingCoordinator.showRecordingTrimmer(for: url)
            },
            hideLauncher: { [weak self] in self?.launcherCoordinator.hide() }
        )
        return AppPreferencesCoordinator(windowCoordinator: windowCoordinator, dependencies: dependencies)
        #endif
    }()
    private var viewModel: LauncherViewModel!
    func applicationDidFinishLaunching(_: Notification) {
        lifecycleCoordinator.applicationDidFinishLaunching()
    }

    private func prepareApplicationForLaunch() {
        FileUploadService.cleanupTemporaryClipboardUploads()
        viewModel = LauncherViewModel(
            settingsStore: settingsStore,
            discoveryService: discoveryService,
            launchHistoryStore: launchHistoryStore,
            clipboardStore: clipboardStore
        )
        viewModel.onOpenPreferences = { [weak self] in
            self?.preferencesCoordinator.show()
        }
        viewModel.onOpenAIChat = { [weak self] input in
            self?.aiChatCoordinator.open(input)
        }
        viewModel.onOpenAuthenticator = { [weak self] in
            self?.launcherCoordinator.hide()
            self?.authenticatorService.showPanel()
        }
        viewModel.onHealthCommand = { [weak self] command in
            self?.healthReminderCoordinator.handle(command)
        }
        viewModel.onScreenshotCommand = { [weak self] command in
            self?.captureCoordinator.handle(command)
        }
        viewModel.onRecordingCommand = { [weak self] command in
            self?.recordingCoordinator.handle(command)
        }
        viewModel.onWhiteboardCommand = { [weak self] command in
            self?.whiteboardCoordinator.handle(command)
        }
        viewModel.onKeepAwakeCommand = { [weak self] in
            self?.keepAwakeCommandCoordinator.handleCommand()
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
            self?.launcherCoordinator.hide()
            self?.clipboardActionCoordinator.uploadFromClipboard()
        }
        viewModel.onPinClipboardImage = { [weak self] image in
            self?.launcherCoordinator.hide()
            self?.pinnedImageController.pin(image)
        }
        viewModel.onRecognizeClipboardImage = { [weak self] image in
            self?.clipboardActionCoordinator.recognizeClipboardImage(image, translate: false)
        }
        viewModel.onTranslateClipboardImage = { [weak self] image in
            self?.clipboardActionCoordinator.recognizeClipboardImage(image, translate: true)
        }
        viewModel.onScanClipboardImageQRCode = { [weak self] image in
            self?.clipboardActionCoordinator.scanClipboardImageQRCode(image)
        }
        viewModel.onEditClipboardImage = { [weak self] image in
            self?.clipboardActionCoordinator.editClipboardImage(image)
        }
        viewModel.onOpenClipboardImage = { [weak self] image in
            self?.clipboardActionCoordinator.openClipboardImage(image)
        }
        viewModel.onSaveClipboardImage = { [weak self] image in
            self?.clipboardActionCoordinator.saveClipboardImageAs(image)
        }
        viewModel.onSendClipboardImageToWhiteboard = { [weak self] image in
            self?.clipboardActionCoordinator.sendImageToWhiteboard(image)
        }
        viewModel.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
        }
        whiteboardFeatureController.onError = { [weak self] error in
            MeowLog.whiteboard.error(
                "Whiteboard error: \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            self?.whiteboardCoordinator.presentError(error.localizedDescription)
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
            self.launcherCoordinator.hide()
            // Small delay to let hide complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.clipboardStore.writeToPasteboard(entry)
                self.launcherCoordinator.simulatePaste()
            }
        }
        viewModel.onCopyText = { [weak self] text in
            guard let self else { return }
            self.launcherCoordinator.hide()
            self.clipboardStore.writePrivateTextToPasteboard(text)
        }
        viewModel.onLaunchApplication = { [weak self] app in
            guard let self else { return }
            self.launcherCoordinator.hide()
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
            self?.textActionCoordinator.presentTextActions(for: text)
        }
        NSApp.servicesProvider = textServiceProvider
    }

    private func applyInitialSettings() {
        let initial = settingsStore.load()
        dockIconService.start(style: initial.dockIconStyle)
        apply(settings: initial)
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

    func applicationWillTerminate(_: Notification) {
        lifecycleCoordinator.applicationWillTerminate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lifecycleCoordinator.applicationShouldTerminate(sender)
    }

    func applicationDidBecomeActive(_: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }

    private func refreshDateUIAfterWake() {
        dockIconService.refresh()
        statusItemService.refreshDateIcon()

        calendarCoordinator.refresh()
    }

    private func setupStatusItem() {
        statusItemService.setup(
            initialSettings: viewModel.settings,
            toggleLauncher: { [weak self] in
                self?.launcherCoordinator.toggle()
            },
            openPreferences: { [weak self] in
                self?.preferencesCoordinator.show()
            },
            showCalendar: { [weak self] in
                self?.calendarCoordinator.togglePopover()
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
                self?.clipboardActionCoordinator.upload(fileURL: url)
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    }

    private func apply(settings: AppSettings) {
        settingsCoordinator.apply(
            settings: settings,
            runtimeState: AppSettingsCoordinator.RuntimeState(
                aiChatHistoryStoreLoaded: aiChatHistoryStoreLoaded,
                captureStoreLoaded: captureStoreLoaded,
                recordingServiceLoaded: recordingServiceLoaded,
                recordingStateShowsControls: recordingStateShowsControls,
                authenticatorServiceLoaded: authenticatorServiceLoaded,
                systemMonitorServiceLoaded: systemMonitorServiceLoaded,
                speechRecognitionServiceLoaded: speechRecognitionServiceLoadedForSettings
            )
        )
    }

    private var speechRecognitionServiceLoadedForSettings: Bool {
        #if MEOW_VOICE
        speechRecognitionServiceLoaded
        #else
        false
        #endif
    }

    private func makeSettingsActions() -> AppSettingsCoordinator.Actions {
        AppSettingsCoordinator.Actions(
            applyLanguage: { [weak self] language, systemMonitorLoaded in
                guard let self else { return }
                LanguageManager.shared.apply(language)
                self.statusItemService.updateL10n()
                self.dockIconService.refresh()
                if systemMonitorLoaded {
                    self.systemMonitorService.refreshLocalization()
                }
                self.windowCoordinator.refreshLocalizedWindowTitles()
                self.viewModel?.refresh()
                self.windowCoordinator.updatePreferencesTitle(L10n.windowPrefsTitle)
            },
            applyDisplaySettings: { [weak self] settings in
                guard let self else { return }
                self.dockService.apply(showDockIcon: settings.showDockIcon)
                self.dockIconService.apply(style: settings.dockIconStyle)
                self.statusItemService.setVisible(settings.showStatusItem)
                self.statusItemService.updateToggleStates(settings)
                self.statusItemService.updateDateIconStyle(settings.dateIconStyle)
            },
            requestUploadNotificationAuthorization: {
                FileUploadNotifications.requestAuthorization()
            },
            setAIChatHistoryPersistence: { [weak self] enabled in
                self?.aiChatHistoryStore.setPersistenceEnabled(enabled)
            },
            applyCaptureRetention: { [weak self] settings in
                self?.captureStore.applyRetention(
                    historyLimit: settings.historyLimit,
                    retentionDays: settings.retentionDays,
                    maxStorageMB: settings.maxStorageMB
                )
            },
            applyRecordingSettings: { [weak self] settings in
                guard let self else { return }
                self.recordingService.apply(settings: settings)
                self.recordingCoordinator.cameraOverlaySettingsDidChange(settings.recording)
                self.recordingCoordinator.magnifierSettingsDidChange(settings.recording)
            },
            setRecordingControlsVisible: { [weak self] visible in
                if visible {
                    self?.recordingCoordinator.showRecordingControl()
                } else {
                    self?.recordingCoordinator.hideRecordingControl()
                }
            },
            applyAuthenticatorSettings: { [weak self] settings in
                self?.authenticatorService.apply(
                    enabled: settings.authenticatorEnabled,
                    iCloudSyncEnabled: settings.authenticatorICloudSyncEnabled,
                    theme: settings.theme
                )
            },
            applySystemMonitorSettings: { [weak self] settings in
                self?.systemMonitorService.apply(settings: settings.systemMonitor, theme: settings.theme)
            },
            applyAlwaysOnServices: { [weak self] settings in
                guard let self else { return }
                self.keystrokeVisualizerService.apply(settings: settings)
                self.healthReminderService.apply(settings: settings)
                self.keepAwakeService.apply(settings: settings.keepAwake)
            },
            applySpeechSettings: { [weak self] settings in
                #if MEOW_VOICE
                guard let self else { return }
                self.speechModelStore.apply(selectedModel: settings.speech.model)
                self.speechRecognitionService.apply(settings: settings.speech)
                #endif
            },
            applyAutoLaunch: { [weak self] enabled in
                self?.autoLaunchService.apply(enabled: enabled) ?? false
            },
            applyHotkeys: { [weak self] settings in
                guard let self else { return }
                self.hotkeyCoordinator.apply(
                    settings: settings,
                    actions: self.hotkeyRouter.makeCoordinatorActions()
                )
            },
            applyWhiteboardSettings: { [weak self] settings in
                guard let self else { return }
                self.whiteboardCoordinator.apply(settings.whiteboard)
                if !settings.whiteboard.normalized().enabled {
                    self.viewModel.setWhiteboardHotkeyRegistrationError(nil)
                }
            },
            configureClipboard: { [weak self] settings in
                self?.clipboardStore.configure(
                    retention: settings.clipboardRetention,
                    imageStorageLimitMB: settings.clipboardImageStorageLimitMB,
                    disabledAppBundleIDs: settings.clipboardDisabledAppBundleIDs
                )
            },
            setClipboardMonitoring: { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.clipboardStore.startMonitoring { [weak self] in
                        self?.viewModel.refresh()
                    }
                } else {
                    self.clipboardStore.stopMonitoring()
                }
            },
            refreshLauncherAfterClipboardChange: { [weak self] in
                self?.viewModel.refresh()
            },
            reconcileAutoLaunch: { [weak self] actualAutoLaunchEnabled in
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.viewModel.settings.autoLaunch != actualAutoLaunchEnabled
                    else { return }
                    self.viewModel.settings.autoLaunch = actualAutoLaunchEnabled
                }
            }
        )
    }

    private func makeMediaCommandRouterActions() -> AppMediaCommandRouter.Actions {
        AppMediaCommandRouter.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            hideLauncher: { [weak self] in self?.launcherCoordinator.hide() },
            hideTransientPanels: { [weak self] in
                self?.launcherCoordinator.hide()
                self?.textActionCoordinator.hideTranslationPanel()
            },
            prepareWhiteboardForCapture: { [weak self] in
                self?.whiteboardCoordinator.prepareForCapture() ?? []
            },
            restoreWhiteboardAfterCapture: { [weak self] in
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
                self?.mediaErrorPresenter.presentScreenshotError(error)
            },
            presentUploadError: { [weak self] error in
                self?.mediaErrorPresenter.presentUploadError(error)
            },
            presentScrollingAccessibilityPrompt: { [weak self] in
                self?.mediaErrorPresenter.presentScrollingCaptureAccessibilityPrompt()
            },
            presentScrollingReducedImageWarning: { [weak self] in
                self?.mediaErrorPresenter.presentScrollingCaptureReducedImageWarning()
            },
            editImage: { [weak self] url in
                self?.clipboardActionCoordinator.editImage(at: url)
            },
            recognizeClipboardImage: { [weak self] image, translate in
                self?.clipboardActionCoordinator.recognizeClipboardImage(image, translate: translate)
            },
            scanClipboardImageQRCode: { [weak self] image in
                self?.clipboardActionCoordinator.scanClipboardImageQRCode(image)
            },
            askAI: { [weak self] url in
                self?.viewModel.openAIChat(
                    prompt: L10n.aiImagePrompt,
                    imagePath: url.path
                )
            },
            sendImageFileToWhiteboard: { [weak self] url, sourceName in
                self?.whiteboardCoordinator.sendImageFile(at: url, sourceName: sourceName)
            },
            captureIsBusy: { [weak self] in self?.captureIsBusy ?? false },
            prepareWhiteboardForRecording: { [weak self] in
                self?.whiteboardCoordinator.prepareForRecording() ?? []
            },
            restoreWhiteboardAfterRecording: { [weak self] in
                self?.whiteboardCoordinator.restoreAfterRecording()
            },
            activeScreen: { [weak self] in self?.windowCoordinator.activeScreen() },
            setSystemAudioMode: { [weak self] in
                self?.viewModel.settings.recording.audioMode = .system
            },
            updateRecordingState: { [weak self] state, elapsed in
                self?.statusItemService.updateRecordingState(state, elapsed: elapsed)
            },
            presentRecordingError: { [weak self] error in
                self?.mediaErrorPresenter.presentRecordingError(error)
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
            stopStatusItem: { [weak self] in
                self?.statusItemService.stop()
            },
            stopDockIcon: { [weak self] in
                self?.dockIconService.stop()
            },
            removeEventMonitors: { [weak self] in
                self?.windowCoordinator.removeEventMonitors()
            },
            shutdownUploads: { [weak self] in
                await self?.fileUploadService.shutdown()
            },
            replyToTermination: { sender in
                sender.reply(toApplicationShouldTerminate: true)
            }
        )
    }

    private func makeClipboardActions() -> AppClipboardActionCoordinator.Actions {
        AppClipboardActionCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            hideLauncher: { [weak self] in
                self?.launcherCoordinator.hide()
            },
            presentTranslation: { [weak self] text, axPermissionDenied, sourceImagePath in
                self?.textActionCoordinator.presentTranslationPanel(
                    text: text,
                    axPermissionDenied: axPermissionDenied,
                    sourceImagePath: sourceImagePath
                )
            },
            presentScreenshotError: { [weak self] error in
                self?.mediaErrorPresenter.presentScreenshotError(error)
            },
            presentUploadError: { [weak self] error in
                self?.mediaErrorPresenter.presentUploadError(error)
            },
            importImageFileToWhiteboard: { [weak self] url, sourceName in
                self?.whiteboardCoordinator.sendImageFile(at: url, sourceName: sourceName)
            },
            onArtifactReady: { [weak self] artifact in
                self?.captureCoordinator.showPostCaptureActionsIfNeeded(for: artifact)
            },
            presentOTPAuthImport: { [weak self] payload in
                self?.authenticatorCoordinator.handleOTPAuthImport(payload)
            },
            presentQRCodePayload: { [weak self] payload in
                self?.authenticatorCoordinator.presentQRCodeResult(payload)
            }
        )
    }

    private func makeTextActions() -> AppTextActionCoordinator.Actions {
        return AppTextActionCoordinator.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            openAIChat: { [weak self] input in
                self?.aiChatCoordinator.open(input)
            }
        )
    }

    private func makeHotkeyRouterActions() -> AppHotkeyRouter.Actions {
        AppHotkeyRouter.Actions(
            settings: { [weak self] in self?.viewModel.settings ?? .default },
            updateSettings: { [weak self] settings in self?.viewModel.settings = settings },
            toggleLauncher: { [weak self] in self?.launcherCoordinator.toggle() },
            openFinder: { [weak self] in self?.launcherCoordinator.openFinder() },
            translate: { [weak self] in self?.textActionCoordinator.triggerTranslation() },
            textActions: { [weak self] in self?.textActionCoordinator.triggerTextActions() },
            scrollingScreenshot: { [weak self] in self?.captureCoordinator.triggerScrollingCapture() },
            screenshot: { [weak self] mode, editAfterCapture, uploadAfterCapture in
                self?.captureCoordinator.triggerScreenshot(
                    mode: mode,
                    editAfterCapture: editAfterCapture,
                    uploadAfterCapture: uploadAfterCapture
                )
            },
            recording: { [weak self] mode in self?.recordingCoordinator.triggerRecording(mode: mode) },
            pauseRecording: { [weak self] in self?.recordingService.pauseOrResume() },
            stopRecording: { [weak self] in
                guard let self else { return }
                Task { await self.recordingService.stop() }
            },
            saveRecordingFrame: { [weak self] in self?.recordingCoordinator.saveCurrentFrame() },
            toggleRecordingMagnifier: { [weak self] in self?.recordingCoordinator.toggleMagnifier() },
            toggleWhiteboard: { [weak self] in self?.whiteboardFeatureController.toggleEditing() },
            speechPressed: { [weak self] in
                #if MEOW_VOICE
                self?.speechRecognitionService.hotkeyPressed()
                #endif
            },
            speechReleased: { [weak self] in
                #if MEOW_VOICE
                self?.speechRecognitionService.hotkeyReleased()
                #endif
            },
            setFinderRegistrationError: { [weak self] in
                self?.viewModel.setFinderHotkeyRegistrationError($0)
            },
            setWhiteboardRegistrationError: { [weak self] in
                self?.viewModel.setWhiteboardHotkeyRegistrationError($0)
            },
            presentTextActionsHotkeyConflict: { [weak self] keyCode, modifiers in
                self?.textActionCoordinator.presentTextActionsHotkeyConflict(
                    keyCode: keyCode,
                    modifiers: modifiers
                )
            }
        )
    }

    private var recordingStateShowsControls: Bool {
        guard recordingServiceLoaded else { return false }
        return recordingCoordinator.recordingStateShowsControls
    }

    private func setupOutsideClickDismissMonitor() {
        windowCoordinator.installEventMonitors(
            actions: AppWindowCoordinator.EventMonitorActions(
                dismissLauncher: { [weak self] in self?.launcherCoordinator.hide() },
                dismissTranslation: { [weak self] in self?.textActionCoordinator.hideTranslationPanel() },
                dismissTextActions: { [weak self] in self?.textActionCoordinator.hideTextActionsPanel() },
                dismissCalendarPopover: { [weak self] in self?.windowCoordinator.dismissCalendarPopover() },
                statusItemButton: { [weak self] in self?.statusItemService.statusItemButton },
                cancelSpeechIfActive: { [weak self] in
                    #if MEOW_VOICE
                    guard let self,
                          self.speechRecognitionServiceLoaded,
                          self.speechRecognitionService.state.isActive
                    else { return false }
                    self.speechRecognitionService.cancel()
                    return true
                    #else
                    false
                    #endif
                },
                showPreferences: { [weak self] in self?.preferencesCoordinator.show(animated: true) }
            )
        )
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

    func openPreferencesFromCommand() {
        preferencesCoordinator.show(animated: true)
    }

}
