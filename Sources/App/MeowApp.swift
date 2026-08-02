import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import WhiteboardFeature

enum MeowWindowIdentifiers {
    static let aiChat = NSUserInterfaceItemIdentifier("meow.ai.chat.window")
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class WindowResignDelegate: NSObject, NSWindowDelegate {
    private let onResign: () -> Void

    init(onResign: @escaping () -> Void) {
        self.onResign = onResign
    }

    func windowDidResignKey(_ notification: Notification) {
        onResign()
    }
}

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
    private let settingsStore = SettingsStore()
    private let dockService = DockService()
    private let dockIconService = DockIconService()
    private let statusItemService = StatusItemService()
    private let discoveryService = AppDiscoveryService()
    private let launchHistoryStore = LaunchHistoryStore()
    private let autoLaunchService = AutoLaunchService()
    private let hotkeyService = HotkeyService()
    private let keystrokeVisualizerService = KeystrokeVisualizerService()
    private let whiteboardFeatureController = WhiteboardFeatureController()
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
    private let healthReminderService = HealthReminderService()
    private let clipboardStore = ClipboardStore()
    private lazy var screenCaptureService = ScreenCaptureService()
    private let captureOverlayController = CaptureOverlayController()
    private lazy var recordingContentPickerController = RecordingContentPickerController()
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
    private lazy var recordingStore = RecordingStore()
    private var recordingServiceLoaded = false
    private lazy var recordingService: RecordingService = {
        recordingServiceLoaded = true
        let service = RecordingService(store: recordingStore)
        configureRecordingService(service)
        service.apply(settings: viewModel.settings)
        recordingNotificationService.requestAuthorization()
        return service
    }()
    private lazy var recordingNotificationService = RecordingNotificationService()
    private let cameraOverlayController = CameraOverlayController()
    private let screenMagnifierController = ScreenMagnifierController()
    private lazy var captureEditorController = CaptureEditorController()
    private lazy var postCaptureActionsController = PostCaptureActionsController()
    private lazy var uploadHistoryStore = UploadHistoryStore()
    private let uploadSuccessHUDController = UploadSuccessHUDController()
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
    private lazy var pinnedImageController = PinnedImageController()
    private lazy var imageRecognitionService = ImageRecognitionService()
    private lazy var preferencesNavigation = PreferencesNavigationState()
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

    private let translationService = TranslationService()
    private let textServiceProvider = TextServiceProvider()

    private var launcherWindow: LauncherPanel?
    private var launcherHostingController: NSHostingController<LauncherView>?
    private var translationWindow: LauncherPanel?
    private var translationHostingController: NSHostingController<AnyView>?
    private var textActionsWindow: LauncherPanel?
    private var textActionsHostingController: NSHostingController<TextActionsPanelView>?
    private var textActionsWindowDelegate: WindowResignDelegate?
    private var aiChatWindow: NSWindow?
    private var aiChatHostingController: NSHostingController<AnyView>?
    private var preferencesWindow: NSWindow?
    private var captureHistoryWindow: NSWindow?
    private var captureHistoryHostingController: NSHostingController<CaptureHistoryView>?
    private var recordingHistoryWindow: NSWindow?
    private var recordingControlWindow: NSPanel?
    private var recordingPreviewWindow: NSPanel?
    private var recordingTrimmerWindows: [URL: NSWindow] = [:]
    private var recordingTrimmerDelegates: [URL: WindowCloseDelegate] = [:]
    private var recordingTask: Task<Void, Never>?
    private var viewModel: LauncherViewModel!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    #if MEOW_VOICE
    private var selectedTextForTts = ""
    private var ttsSelectionPermissionDenied = false
    private var lastRegisteredTtsHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredSpeechHotkey: (keyCode: UInt32, modifiers: UInt32)?
    #endif
    private var appliedLanguage: AppLanguage?
    private var lastRegisteredToggleHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredTranslateHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredTextActionsHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredScreenshotRegionHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredScreenshotEditHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredScreenshotWindowHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredScreenshotDisplayHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingDisplayHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingRegionHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingWindowHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingPauseHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingStopHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingFrameHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredRecordingMagnifierHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredUploadHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredWhiteboardHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var recordingAllowsVisualOverlays = false
    private var whiteboardPreparedForRecording = false
    private var captureTask: Task<Void, Never>?
    private var clipboardMonitoringEnabled = false
    private var calendarPopover: NSPopover?
    private var calendarPopoverController: NSHostingController<CalendarPopoverView>?
    private var calendarRefreshToken = UUID()
    private var workspaceWakeObserver: NSObjectProtocol?
    private var uploadShutdownForTermination = false
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
        observeSystemWake()
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
            self?.recordingAllowsVisualOverlays = false
            self?.recordingNotificationService.notifyCompleted(artifact)
            if self?.viewModel.settings.recording.showPreview == true {
                self?.showRecordingPreview(artifact)
            }
        }
        service.onError = { [weak self] error in
            self?.restoreWhiteboardAfterRecording()
            self?.hideRecordingControl()
            self?.cameraOverlayController.stop()
            self?.screenMagnifierController.stop()
            self?.recordingAllowsVisualOverlays = false
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
        whiteboardFeatureController.shutdown()
        hotkeyService.unregister()
        fileUploadService.cancel()
        captureTask?.cancel()
        recordingTask?.cancel()
        if recordingServiceLoaded, recordingService.state.isActive {
            Task { await recordingService.stop() }
        }
        cameraOverlayController.stop()
        screenMagnifierController.stop()
        captureOverlayController.cancel()
        captureEditorController.cancel()
        postCaptureActionsController.close()
        pinnedImageController.closeAll()
        #if MEOW_VOICE
        if speechRecognitionServiceLoaded {
            speechRecognitionService.cancel()
        }
        if speechSynthesisServiceLoaded {
            speechSynthesisService.cancel()
        }
        speechOverlayController.hide()
        #endif
        keystrokeVisualizerService.stop()
        healthReminderService.stop()
        clipboardStore.stopMonitoring()
        dockIconService.stop()
        if let workspaceWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeObserver)
            self.workspaceWakeObserver = nil
        }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !uploadShutdownForTermination else { return .terminateNow }
        uploadShutdownForTermination = true
        Task { @MainActor [weak self, weak sender] in
            await self?.fileUploadService.shutdown()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_: Notification) {
        keystrokeVisualizerService.retryAfterPermissionChange()
        #if MEOW_VOICE
        if speechRecognitionServiceLoaded || viewModel.settings.speech.enabled {
            speechRecognitionService.refreshPermissionState()
        }
        #endif
    }

    private func observeSystemWake() {
        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDateUIAfterWake()
            }
        }
    }

    private func refreshDateUIAfterWake() {
        dockIconService.refresh()
        statusItemService.refreshDateIcon()

        guard let hosting = calendarPopoverController,
              calendarPopover?.isShown == true
        else { return }

        calendarRefreshToken = UUID()
        hosting.rootView = makeCalendarPopoverView(for: calendarPopover)
    }

    private func createLauncherWindow() {
        guard launcherWindow == nil else { return }

        let window = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        centerWindowOnScreen(window)
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 20
            contentView.layer?.masksToBounds = true
        }
        launcherWindow = window
        attachLauncherContentIfNeeded()
    }

    private func attachLauncherContentIfNeeded() {
        guard launcherHostingController == nil else { return }
        guard let launcherWindow else { return }

        let content = LauncherView(viewModel: viewModel) { [weak self] in
            self?.hideLauncher()
        }
        let hosting = NSHostingController(rootView: content)
        launcherHostingController = hosting
        launcherWindow.contentViewController = hosting
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
            toggleDockIcon: { [weak self] in
                guard let self else { return }
                self.viewModel.settings.showDockIcon.toggle()
            },
            toggleStatusBarIcon: { [weak self] in
                guard let self else { return }
                self.viewModel.settings.showStatusItem.toggle()
            },
            toggleWhiteboard: { [weak self] in
                self?.whiteboardFeatureController.toggleEditing()
            },
            pauseRecording: { [weak self] in
                self?.runOnMain { $0.recordingService.pauseOrResume() }
            },
            stopRecording: { [weak self] in
                self?.runOnMain { app in
                    Task { await app.recordingService.stop() }
                }
            },
            openRecordingHistory: { [weak self] in
                self?.showRecordingHistory()
            },
            uploadDroppedFile: { [weak self] url in
                guard self?.viewModel.settings.fileHosting.s3.isEnabled == true else { return }
                self?.upload(fileURL: url)
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
        statusItemService.onDateIconStyleChanged = { [weak self] style in
            guard let self else { return }
            self.viewModel.settings.dateIconStyle = style
        }
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
            viewModel?.refresh()
            preferencesWindow?.title = L10n.windowPrefsTitle
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
        keystrokeVisualizerService.apply(settings: settings)
        healthReminderService.apply(settings: settings)
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
        let toggleHotkeyResult = hotkeyService.registerToggleHotkey(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        ) { [weak self] in
            self?.toggleLauncher()
        }
        handleHotkeyRegistrationResult(
            toggleHotkeyResult,
            name: "launcher",
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers,
            previous: lastRegisteredToggleHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.updateLauncherHotkey(keyCode: keyCode, modifiers: modifiers)
        } onSuccess: { [weak self] in
            self?.lastRegisteredToggleHotkey = (settings.hotkeyKeyCode, settings.hotkeyModifiers)
        }

        let translateHotkeyResult = hotkeyService.registerTranslateHotkey(
            keyCode: settings.translateHotkeyKeyCode,
            modifiers: settings.translateHotkeyModifiers
        ) { [weak self] in
            self?.triggerTranslation()
        }

        let textActionsHotkeyResult = hotkeyService.registerTextActionsHotkey(
            keyCode: settings.textActionsHotkeyKeyCode,
            modifiers: settings.textActionsHotkeyModifiers
        ) { [weak self] in
            self?.triggerTextActions()
        }

        #if MEOW_VOICE
        if settings.speech.enabled {
            let speechHotkeyResult = hotkeyService.registerSpeechHotkey(
                keyCode: settings.speech.hotkeyKeyCode,
                modifiers: settings.speech.hotkeyModifiers,
                pressedAction: { [weak self] in
                    self?.speechRecognitionService.hotkeyPressed()
                },
                releasedAction: { [weak self] in
                    self?.speechRecognitionService.hotkeyReleased()
                }
            )
            handleHotkeyRegistrationResult(
                speechHotkeyResult,
                name: "speech",
                keyCode: settings.speech.hotkeyKeyCode,
                modifiers: settings.speech.hotkeyModifiers,
                previous: lastRegisteredSpeechHotkey
            ) { [weak self] keyCode, modifiers in
                guard let self else { return }
                self.viewModel.settings.speech.hotkeyKeyCode = keyCode
                self.viewModel.settings.speech.hotkeyModifiers = modifiers
            } onSuccess: { [weak self] in
                self?.lastRegisteredSpeechHotkey = (
                    settings.speech.hotkeyKeyCode,
                    settings.speech.hotkeyModifiers
                )
            }
        } else {
            hotkeyService.unregisterSpeechHotkey()
            lastRegisteredSpeechHotkey = nil
        }
        #else
        hotkeyService.unregisterSpeechHotkey()
        #endif
        handleHotkeyRegistrationResult(
            translateHotkeyResult,
            name: "translation",
            keyCode: settings.translateHotkeyKeyCode,
            modifiers: settings.translateHotkeyModifiers,
            previous: lastRegisteredTranslateHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.updateTranslateHotkey(keyCode: keyCode, modifiers: modifiers)
        } onSuccess: { [weak self] in
            self?.lastRegisteredTranslateHotkey = (
                settings.translateHotkeyKeyCode,
                settings.translateHotkeyModifiers
            )
        }

        handleHotkeyRegistrationResult(
            textActionsHotkeyResult,
            name: "selected-text actions",
            keyCode: settings.textActionsHotkeyKeyCode,
            modifiers: settings.textActionsHotkeyModifiers,
            previous: lastRegisteredTextActionsHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.updateTextActionsHotkey(keyCode: keyCode, modifiers: modifiers)
        } onSuccess: { [weak self] in
            self?.lastRegisteredTextActionsHotkey = (
                settings.textActionsHotkeyKeyCode,
                settings.textActionsHotkeyModifiers
            )
        }
        if case .failed = textActionsHotkeyResult {
            presentTextActionsHotkeyConflict(
                keyCode: settings.textActionsHotkeyKeyCode,
                modifiers: settings.textActionsHotkeyModifiers
            )
        }

        #if MEOW_VOICE
        if normalizedTTSSettings.enabled {
            let ttsHotkeyResult = hotkeyService.registerTtsSelectionHotkey(
                keyCode: settings.ttsHotkeyKeyCode,
                modifiers: settings.ttsHotkeyModifiers
            ) { [weak self] in
                self?.speakSelectedTextViaHotkey()
            }
            handleHotkeyRegistrationResult(
                ttsHotkeyResult,
                name: "text-to-speech",
                keyCode: settings.ttsHotkeyKeyCode,
                modifiers: settings.ttsHotkeyModifiers,
                previous: lastRegisteredTtsHotkey
            ) { [weak self] keyCode, modifiers in
                guard let self else { return }
                self.viewModel.settings.ttsHotkeyKeyCode = keyCode
                self.viewModel.settings.ttsHotkeyModifiers = modifiers
            } onSuccess: { [weak self] in
                self?.lastRegisteredTtsHotkey = (
                    settings.ttsHotkeyKeyCode,
                    settings.ttsHotkeyModifiers
                )
            }
        } else {
            hotkeyService.unregisterTtsSelectionHotkey()
            lastRegisteredTtsHotkey = nil
        }
        #else
        hotkeyService.unregisterTtsSelectionHotkey()
        #endif

        applyScreenshotHotkeys(settings.screenshot)
        applyRecordingHotkeys(settings.recording)
        applyUploadHotkey(settings.fileHosting)
        applyWhiteboard(settings.whiteboard)

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

    private func handleHotkeyRegistrationResult(
        _ result: HotkeyService.RegistrationResult,
        name: String,
        keyCode: UInt32,
        modifiers: UInt32,
        previous: (keyCode: UInt32, modifiers: UInt32)?,
        restore: @escaping (UInt32, UInt32) -> Void,
        onSuccess: () -> Void
    ) {
        switch result {
        case .registered:
            onSuccess()
        case let .failed(status):
            NSLog("[Meow] Failed to register \(name) hotkey: \(status)")
            guard let previous,
                  previous.keyCode != keyCode || previous.modifiers != modifiers
            else { return }
            restore(previous.keyCode, previous.modifiers)
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
            hotkeyService.unregisterWhiteboardHotkey()
            lastRegisteredWhiteboardHotkey = nil
            viewModel.setWhiteboardHotkeyRegistrationError(nil)
            return
        }

        let result = hotkeyService.registerWhiteboardHotkey(
            keyCode: normalized.hotkeyKeyCode,
            modifiers: normalized.hotkeyModifiers
        ) { [weak self] in
            self?.whiteboardFeatureController.toggleEditing()
        }
        handleHotkeyRegistrationResult(
            result,
            name: "whiteboard",
            keyCode: normalized.hotkeyKeyCode,
            modifiers: normalized.hotkeyModifiers,
            previous: lastRegisteredWhiteboardHotkey
        ) { [weak self] keyCode, modifiers in
            guard let self else { return }
            self.viewModel.settings.whiteboard.hotkeyKeyCode = keyCode
            self.viewModel.settings.whiteboard.hotkeyModifiers = modifiers
        } onSuccess: { [weak self] in
            self?.viewModel.setWhiteboardHotkeyRegistrationError(nil)
            self?.lastRegisteredWhiteboardHotkey = (
                normalized.hotkeyKeyCode,
                normalized.hotkeyModifiers
            )
        }
        if case let .failed(status) = result {
            viewModel.setWhiteboardHotkeyRegistrationError(
                String(format: L10n.whiteboardHotkeyError, status)
            )
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
        guard viewModel.settings.whiteboard.enabled else { return }
        hideLauncher()
        let path = image.originalPath ?? image.thumbnailPath
        sendImageFileToWhiteboard(at: URL(fileURLWithPath: path), sourceName: image.sourceName)
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

    private func applyScreenshotHotkeys(_ settings: ScreenshotSettings) {
        guard settings.enabled else {
            hotkeyService.unregisterScreenshotHotkeys()
            lastRegisteredScreenshotRegionHotkey = nil
            lastRegisteredScreenshotEditHotkey = nil
            lastRegisteredScreenshotWindowHotkey = nil
            lastRegisteredScreenshotDisplayHotkey = nil
            return
        }

        let regionResult = hotkeyService.registerScreenshotRegionHotkey(
            keyCode: settings.regionHotkeyKeyCode,
            modifiers: settings.regionHotkeyModifiers
        ) { [weak self] in
            guard let self else { return }
            triggerScreenshot(mode: viewModel.settings.screenshot.defaultCaptureMode)
        }
        handleHotkeyRegistrationResult(
            regionResult,
            name: "screenshot region",
            keyCode: settings.regionHotkeyKeyCode,
            modifiers: settings.regionHotkeyModifiers,
            previous: lastRegisteredScreenshotRegionHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.settings.screenshot.regionHotkeyKeyCode = keyCode
            self?.viewModel.settings.screenshot.regionHotkeyModifiers = modifiers
        } onSuccess: { [weak self] in
            self?.lastRegisteredScreenshotRegionHotkey = (
                settings.regionHotkeyKeyCode,
                settings.regionHotkeyModifiers
            )
        }

        let windowResult = hotkeyService.registerScreenshotWindowHotkey(
            keyCode: settings.windowHotkeyKeyCode,
            modifiers: settings.windowHotkeyModifiers
        ) { [weak self] in
            self?.triggerScreenshot(mode: .window)
        }

        let editResult = hotkeyService.registerScreenshotEditHotkey(
            keyCode: settings.editHotkeyKeyCode,
            modifiers: settings.editHotkeyModifiers
        ) { [weak self] in
            guard let self else { return }
            triggerScreenshot(
                mode: viewModel.settings.screenshot.defaultCaptureMode,
                editAfterCapture: true
            )
        }
        handleHotkeyRegistrationResult(
            editResult,
            name: "screenshot edit",
            keyCode: settings.editHotkeyKeyCode,
            modifiers: settings.editHotkeyModifiers,
            previous: lastRegisteredScreenshotEditHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.settings.screenshot.editHotkeyKeyCode = keyCode
            self?.viewModel.settings.screenshot.editHotkeyModifiers = modifiers
        } onSuccess: { [weak self] in
            self?.lastRegisteredScreenshotEditHotkey = (
                settings.editHotkeyKeyCode,
                settings.editHotkeyModifiers
            )
        }
        handleHotkeyRegistrationResult(
            windowResult,
            name: "screenshot window",
            keyCode: settings.windowHotkeyKeyCode,
            modifiers: settings.windowHotkeyModifiers,
            previous: lastRegisteredScreenshotWindowHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.settings.screenshot.windowHotkeyKeyCode = keyCode
            self?.viewModel.settings.screenshot.windowHotkeyModifiers = modifiers
        } onSuccess: { [weak self] in
            self?.lastRegisteredScreenshotWindowHotkey = (
                settings.windowHotkeyKeyCode,
                settings.windowHotkeyModifiers
            )
        }

        let displayResult = hotkeyService.registerScreenshotDisplayHotkey(
            keyCode: settings.displayHotkeyKeyCode,
            modifiers: settings.displayHotkeyModifiers
        ) { [weak self] in
            self?.triggerScreenshot(mode: .display)
        }
        handleHotkeyRegistrationResult(
            displayResult,
            name: "screenshot display",
            keyCode: settings.displayHotkeyKeyCode,
            modifiers: settings.displayHotkeyModifiers,
            previous: lastRegisteredScreenshotDisplayHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.settings.screenshot.displayHotkeyKeyCode = keyCode
            self?.viewModel.settings.screenshot.displayHotkeyModifiers = modifiers
        } onSuccess: { [weak self] in
            self?.lastRegisteredScreenshotDisplayHotkey = (
                settings.displayHotkeyKeyCode,
                settings.displayHotkeyModifiers
            )
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
            recordingService.pauseOrResume()
        case .stop:
            Task { await recordingService.stop() }
        case .saveCurrentFrame:
            saveRecordingFrame()
        case .toggleMagnifier:
            toggleRecordingMagnifier()
        case .openHistory:
            showRecordingHistory()
        }
    }

    private func applyRecordingHotkeys(_ settings: RecordingSettings) {
        guard settings.enabled else {
            hotkeyService.unregisterRecordingHotkeys()
            lastRegisteredRecordingDisplayHotkey = nil
            lastRegisteredRecordingRegionHotkey = nil
            lastRegisteredRecordingWindowHotkey = nil
            lastRegisteredRecordingPauseHotkey = nil
            lastRegisteredRecordingStopHotkey = nil
            lastRegisteredRecordingFrameHotkey = nil
            lastRegisteredRecordingMagnifierHotkey = nil
            return
        }

        registerRecordingHotkey(
            hotkeyService.registerRecordingDisplayHotkey(
                keyCode: settings.displayHotkeyKeyCode,
                modifiers: settings.displayHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { $0.triggerRecording(mode: .display) }
            },
            name: "recording display",
            keyCode: settings.displayHotkeyKeyCode,
            modifiers: settings.displayHotkeyModifiers,
            previous: lastRegisteredRecordingDisplayHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.displayHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.displayHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingDisplayHotkey = (
                    settings.displayHotkeyKeyCode,
                    settings.displayHotkeyModifiers
                )
            }
        )
        registerRecordingHotkey(
            hotkeyService.registerRecordingFrameHotkey(
                keyCode: settings.frameHotkeyKeyCode,
                modifiers: settings.frameHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { $0.saveRecordingFrame() }
            },
            name: "recording frame",
            keyCode: settings.frameHotkeyKeyCode,
            modifiers: settings.frameHotkeyModifiers,
            previous: lastRegisteredRecordingFrameHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.frameHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.frameHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingFrameHotkey = (
                    settings.frameHotkeyKeyCode,
                    settings.frameHotkeyModifiers
                )
            }
        )
        registerRecordingHotkey(
            hotkeyService.registerRecordingMagnifierHotkey(
                keyCode: settings.magnifierHotkeyKeyCode,
                modifiers: settings.magnifierHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { $0.toggleRecordingMagnifier() }
            },
            name: "recording magnifier",
            keyCode: settings.magnifierHotkeyKeyCode,
            modifiers: settings.magnifierHotkeyModifiers,
            previous: lastRegisteredRecordingMagnifierHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.magnifierHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.magnifierHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingMagnifierHotkey = (
                    settings.magnifierHotkeyKeyCode,
                    settings.magnifierHotkeyModifiers
                )
            }
        )
        registerRecordingHotkey(
            hotkeyService.registerRecordingRegionHotkey(
                keyCode: settings.regionHotkeyKeyCode,
                modifiers: settings.regionHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { $0.triggerRecording(mode: .region) }
            },
            name: "recording region",
            keyCode: settings.regionHotkeyKeyCode,
            modifiers: settings.regionHotkeyModifiers,
            previous: lastRegisteredRecordingRegionHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.regionHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.regionHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingRegionHotkey = (
                    settings.regionHotkeyKeyCode,
                    settings.regionHotkeyModifiers
                )
            }
        )
        registerRecordingHotkey(
            hotkeyService.registerRecordingWindowHotkey(
                keyCode: settings.windowHotkeyKeyCode,
                modifiers: settings.windowHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { $0.triggerRecording(mode: .window) }
            },
            name: "recording window",
            keyCode: settings.windowHotkeyKeyCode,
            modifiers: settings.windowHotkeyModifiers,
            previous: lastRegisteredRecordingWindowHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.windowHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.windowHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingWindowHotkey = (
                    settings.windowHotkeyKeyCode,
                    settings.windowHotkeyModifiers
                )
            }
        )
        registerRecordingHotkey(
            hotkeyService.registerRecordingPauseHotkey(
                keyCode: settings.pauseHotkeyKeyCode,
                modifiers: settings.pauseHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { $0.recordingService.pauseOrResume() }
            },
            name: "recording pause",
            keyCode: settings.pauseHotkeyKeyCode,
            modifiers: settings.pauseHotkeyModifiers,
            previous: lastRegisteredRecordingPauseHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.pauseHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.pauseHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingPauseHotkey = (
                    settings.pauseHotkeyKeyCode,
                    settings.pauseHotkeyModifiers
                )
            }
        )
        registerRecordingHotkey(
            hotkeyService.registerRecordingStopHotkey(
                keyCode: settings.stopHotkeyKeyCode,
                modifiers: settings.stopHotkeyModifiers
            ) { [weak self] in
                self?.runOnMain { app in
                    Task { await app.recordingService.stop() }
                }
            },
            name: "recording stop",
            keyCode: settings.stopHotkeyKeyCode,
            modifiers: settings.stopHotkeyModifiers,
            previous: lastRegisteredRecordingStopHotkey,
            restore: { [weak self] keyCode, modifiers in
                self?.viewModel.settings.recording.stopHotkeyKeyCode = keyCode
                self?.viewModel.settings.recording.stopHotkeyModifiers = modifiers
            },
            success: { [weak self] in
                self?.lastRegisteredRecordingStopHotkey = (
                    settings.stopHotkeyKeyCode,
                    settings.stopHotkeyModifiers
                )
            }
        )
    }

    private func registerRecordingHotkey(
        _ result: HotkeyService.RegistrationResult,
        name: String,
        keyCode: UInt32,
        modifiers: UInt32,
        previous: (keyCode: UInt32, modifiers: UInt32)?,
        restore: @escaping (UInt32, UInt32) -> Void,
        success: () -> Void
    ) {
        handleHotkeyRegistrationResult(
            result,
            name: name,
            keyCode: keyCode,
            modifiers: modifiers,
            previous: previous,
            restore: restore,
            onSuccess: success
        )
    }

    nonisolated private func runOnMain(_ action: @escaping @MainActor (AppDelegate) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            action(self)
        }
    }

    private func triggerRecording(mode: ScreenshotCaptureMode) {
        guard recordingTask == nil,
              captureTask == nil,
              !recordingService.state.isActive
        else { return }
        hideLauncher()
        hideTranslationPanel()

        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recordingTask = nil }
            do {
                let whiteboardWindowIDs = mode.includesApplicationOverlays
                    ? prepareWhiteboardForRecording()
                    : []
                let session = try await screenCaptureService.prepareSession(
                    includingApplicationWindowIDs: whiteboardWindowIDs
                )
                guard let selection = await captureOverlayController.present(session: session, mode: mode) else {
                    restoreWhiteboardAfterRecording()
                    return
                }
                let source: RecordingSource
                switch selection {
                case let .display(display, _):
                    source = .display(display)
                case let .region(display, rect, scale):
                    source = .region(display: display, rectInDisplayPoints: rect, scale: scale)
                case let .window(window, _):
                    source = .window(window)
                }
                recordingAllowsVisualOverlays = source.kind == .display || source.kind == .region
                try await prepareCameraOverlayIfNeeded(for: source)
                await recordingService.start(source: source)
                if recordingService.state.isActive {
                    showRecordingControlIfNeeded()
                } else {
                    restoreWhiteboardAfterRecording()
                }
            } catch {
                restoreWhiteboardAfterRecording()
                presentRecordingError(error)
            }
        }
    }

    private func triggerApplicationRecording() {
        guard recordingTask == nil,
              captureTask == nil,
              !recordingService.state.isActive
        else { return }
        hideLauncher()

        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recordingTask = nil }
            do {
                let session = try await screenCaptureService.prepareSession()
                let applications = applicationCandidates(from: session)
                guard let application = chooseApplication(from: applications),
                      let display = displayAtPointer(in: session)
                else {
                    restoreWhiteboardAfterRecording()
                    return
                }
                let source = RecordingSource.application(application, display: display)
                recordingAllowsVisualOverlays = false
                try await prepareCameraOverlayIfNeeded(for: source)
                await recordingService.start(source: source)
                if recordingService.state.isActive {
                    showRecordingControlIfNeeded()
                } else {
                    restoreWhiteboardAfterRecording()
                }
            } catch {
                restoreWhiteboardAfterRecording()
                presentRecordingError(error)
            }
        }
    }

    private func triggerMultipleWindowRecording() {
        guard recordingTask == nil,
              captureTask == nil,
              !recordingService.state.isActive
        else { return }
        hideLauncher()
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recordingTask = nil }
            guard let filter = await recordingContentPickerController.selectMultipleWindows() else {
                return
            }
            recordingAllowsVisualOverlays = false
            await recordingService.start(source: .contentFilter(filter))
            if recordingService.state.isActive {
                showRecordingControlIfNeeded()
            } else {
                restoreWhiteboardAfterRecording()
            }
        }
    }

    private func triggerSystemAudioRecording() {
        guard recordingTask == nil,
              captureTask == nil,
              !recordingService.state.isActive
        else { return }
        if !viewModel.settings.recording.audioMode.capturesSystemAudio {
            viewModel.settings.recording.audioMode = .system
        }
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recordingTask = nil }
            do {
                let session = try await screenCaptureService.prepareSession()
                guard let display = displayAtPointer(in: session) else {
                    throw RecordingError.sourceUnavailable
                }
                await recordingService.start(source: .systemAudio(display))
                if recordingService.state.isActive {
                    showRecordingControlIfNeeded()
                } else {
                    restoreWhiteboardAfterRecording()
                }
            } catch {
                restoreWhiteboardAfterRecording()
                presentRecordingError(error)
            }
        }
    }

    private func triggerMobileDeviceRecording() {
        guard recordingTask == nil,
              captureTask == nil,
              !recordingService.state.isActive
        else { return }
        let devices = RecordingService.mobileDevices()
        guard let device = chooseMobileDevice(from: devices) else { return }
        hideLauncher()
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.recordingTask = nil }
            await recordingService.start(source: .mobileDevice(device.uniqueID))
            if recordingService.state.isActive {
                showRecordingControlIfNeeded()
            }
        }
    }

    private func applicationCandidates(from session: CaptureSession) -> [SCRunningApplication] {
        var seen = Set<String>()
        return session.windows
            .compactMap(\.owningApplication)
            .filter { application in
                guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
                return seen.insert(application.bundleIdentifier).inserted
            }
            .sorted {
                $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
            }
    }

    private func chooseApplication(
        from applications: [SCRunningApplication]
    ) -> SCRunningApplication? {
        guard !applications.isEmpty else {
            presentRecordingError(RecordingError.sourceUnavailable)
            return nil
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        for application in applications {
            picker.addItem(withTitle: application.applicationName)
        }
        let alert = NSAlert()
        alert.messageText = L10n.recordingChooseApplicationTitle
        alert.informativeText = L10n.recordingChooseApplicationSubtitle
        alert.accessoryView = picker
        alert.addButton(withTitle: L10n.recordingStart)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selectedIndex = picker.indexOfSelectedItem
        guard applications.indices.contains(selectedIndex) else { return nil }
        return applications[selectedIndex]
    }

    private func chooseMobileDevice(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        guard !devices.isEmpty else {
            presentRecordingError(RecordingError.sourceUnavailable)
            return nil
        }
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        for device in devices {
            picker.addItem(withTitle: device.localizedName)
        }
        let alert = NSAlert()
        alert.messageText = L10n.recordingChooseMobileTitle
        alert.informativeText = L10n.recordingChooseMobileSubtitle
        alert.accessoryView = picker
        alert.addButton(withTitle: L10n.recordingStart)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let selectedIndex = picker.indexOfSelectedItem
        guard devices.indices.contains(selectedIndex) else { return nil }
        return devices[selectedIndex]
    }

    private func displayAtPointer(in session: CaptureSession) -> SCDisplay? {
        let point = NSEvent.mouseLocation
        return session.displays.first { $0.screen.frame.contains(point) }?.display
            ?? session.displays.first?.display
    }

    private func prepareCameraOverlayIfNeeded(for source: RecordingSource) async throws {
        guard viewModel.settings.recording.cameraOverlayEnabled,
              source.kind == .display || source.kind == .region
        else {
            cameraOverlayController.stop()
            return
        }
        let display: SCDisplay?
        switch source {
        case let .display(value), let .region(value, _, _), let .systemAudio(value):
            display = value
        case let .application(_, value):
            display = value
        case .contentFilter:
            display = nil
        case .window:
            display = nil
        case .mobileDevice:
            display = nil
        }
        try await cameraOverlayController.start(
            deviceID: viewModel.settings.recording.cameraDeviceID,
            shape: viewModel.settings.recording.cameraOverlayShape,
            on: display.flatMap { ScreenCaptureService.screen(for: $0.displayID) } ?? activeScreen()
        )
    }

    private func toggleRecordingMagnifier() {
        guard recordingService.state.isActive, recordingAllowsVisualOverlays else {
            screenMagnifierController.stop()
            return
        }
        Task { await screenMagnifierController.toggle() }
    }

    private func saveRecordingFrame() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await recordingService.saveCurrentFrame()
            } catch {
                NSLog("[Meow] Failed to save recording frame: %@", String(describing: error))
                presentRecordingError(error)
            }
        }
    }

    private func showRecordingControlIfNeeded() {
        if viewModel.settings.recording.showFloatingControls {
            showRecordingControl()
        } else {
            hideRecordingControl()
        }
    }

    private var recordingStateShowsControls: Bool {
        guard recordingServiceLoaded else { return false }
        switch recordingService.state {
        case .recording, .paused:
            return true
        default:
            return false
        }
    }

    private func showRecordingControl() {
        if recordingControlWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 190, height: 54),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(
                rootView: RecordingControlView(
                    service: recordingService,
                    onStop: { [weak self] in
                        Task { await self?.recordingService.stop() }
                    },
                    onSaveFrame: { [weak self] in
                        self?.saveRecordingFrame()
                    }
                )
            )
            recordingControlWindow = panel
        }
        guard let panel = recordingControlWindow else { return }
        if let screen = activeScreen() {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.maxY - panel.frame.height - 16
            ))
        }
        panel.orderFrontRegardless()
    }

    private func hideRecordingControl() {
        recordingControlWindow?.orderOut(nil)
    }

    private func showRecordingPreview(_ artifact: RecordingArtifact) {
        recordingPreviewWindow?.orderOut(nil)
        let panelSize = recordingPreviewPanelSize(for: artifact)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.recordingPreviewTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        if let screen = activeScreen() {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - panel.frame.width - 24,
                y: screen.visibleFrame.maxY - panel.frame.height - 24
            ))
        } else {
            panel.center()
        }
        recordingPreviewWindow = panel
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.contentViewController = NSHostingController(
                rootView: RecordingPreviewView(
                    artifact: artifact,
                    onTrim: { [weak self, weak panel] in
                        panel?.orderOut(nil)
                        self?.showRecordingTrimmer(for: artifact.fileURL)
                    },
                    onClose: { [weak panel] in panel?.orderOut(nil) }
                )
            )
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func recordingPreviewPanelSize(for artifact: RecordingArtifact) -> NSSize {
        guard artifact.width > 0, artifact.height > 0 else {
            return NSSize(width: 560, height: 260)
        }
        let aspectRatio = CGFloat(artifact.height) / CGFloat(artifact.width)
        let width: CGFloat = 640
        let previewHeight = min(420, max(220, width * aspectRatio))
        return NSSize(width: width, height: previewHeight + 104)
    }

    private func showRecordingHistory() {
        if recordingHistoryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.recordingHistoryTitle
            window.isReleasedWhenClosed = false
            recordingHistoryWindow = window
        }
        guard let window = recordingHistoryWindow else { return }
        centerWindowOnScreen(window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.contentViewController = NSHostingController(
                rootView: RecordingHistoryView(
                    store: self.recordingStore,
                    theme: self.viewModel.settings.theme,
                    onDelete: { [weak self] artifact in
                        self?.recordingStore.delete(artifact)
                    },
                    onTrim: { [weak self] artifact in
                        self?.showRecordingTrimmer(for: artifact.fileURL)
                    }
                )
            )
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showRecordingTrimmer(for url: URL) {
        if let existing = recordingTrimmerWindows[url] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.contentViewController = NSHostingController(
            rootView: RecordingTrimmerView(sourceURL: url)
        )
        window.isReleasedWhenClosed = false
        let delegate = WindowCloseDelegate { [weak self] in
            self?.recordingTrimmerWindows[url] = nil
            self?.recordingTrimmerDelegates[url] = nil
        }
        window.delegate = delegate
        centerWindowOnScreen(window)
        recordingTrimmerWindows[url] = window
        recordingTrimmerDelegates[url] = delegate
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        guard captureTask == nil else { return }
        hideLauncher()
        hideTranslationPanel()

        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var whiteboardPrepared = false
            defer {
                if whiteboardPrepared {
                    self.whiteboardFeatureController.restoreAfterScreenCapture()
                }
                self.captureTask = nil
            }

            do {
                let includedWhiteboardWindowIDs = mode.includesApplicationOverlays
                    ? prepareWhiteboardForCapture()
                    : []
                whiteboardPrepared = mode.includesApplicationOverlays
                    && viewModel.settings.whiteboard.enabled
                let session = try await screenCaptureService.prepareSession(
                    includingApplicationWindowIDs: includedWhiteboardWindowIDs
                )
                guard !Task.isCancelled else { return }
                guard let selection = await captureOverlayController.present(session: session, mode: mode) else {
                    return
                }
                guard !Task.isCancelled else { return }

                let (capturedImage, kind) = try await screenCaptureService.capture(
                    selection,
                    session: session,
                    includeWindowShadow: viewModel.settings.screenshot.includeWindowShadow
                )
                whiteboardFeatureController.restoreAfterScreenCapture()
                whiteboardPrepared = false
                let outputImage: CGImage
                let outputKind: CaptureArtifactKind
                if editAfterCapture {
                    guard let edited = await captureEditorController.present(source: capturedImage) else {
                        return
                    }
                    outputImage = edited
                    outputKind = .edited
                } else {
                    outputImage = capturedImage
                    outputKind = kind
                }
                let artifact = try processCapturedImage(outputImage, kind: outputKind)
                if uploadAfterCapture {
                    try await fileUploadService.upload(fileURL: artifact.imageURL)
                } else {
                    showPostCaptureActionsIfNeeded(for: artifact)
                }
            } catch {
                if uploadAfterCapture {
                    presentUploadError(error)
                } else {
                    presentScreenshotError(error)
                }
            }
        }
    }

    private func processCapturedImage(
        _ image: CGImage,
        kind: CaptureArtifactKind
    ) throws -> CaptureArtifact {
        let settings = viewModel.settings.screenshot
        var externalURL: URL?

        if settings.outputMode == .save || settings.outputMode == .copyAndSave {
            externalURL = try captureStore.saveExternal(image: image, settings: settings)
        }

        let artifact: CaptureArtifact
        do {
            artifact = try captureStore.saveInternal(
                image: image,
                kind: kind,
                historyLimit: settings.historyLimit,
                retentionDays: settings.retentionDays,
                maxStorageMB: settings.maxStorageMB
            )
        } catch {
            if let externalURL {
                try? FileManager.default.removeItem(at: externalURL)
            }
            throw error
        }

        if viewModel.settings.clipboardHistoryEnabled {
            clipboardStore.insertCapture(artifact)
        }
        switch settings.outputMode {
        case .copy:
            clipboardStore.writeCaptureToPasteboard(artifact)
        case .save:
            break
        case .copyAndSave:
            clipboardStore.writeCaptureToPasteboard(artifact)
        }

        if settings.playSound {
            NSSound(named: NSSound.Name("Grab"))?.play()
        }
        viewModel.refresh()
        if settings.automaticallyIndexOCRText {
            indexCaptureText(artifact)
        }
        return artifact
    }

    private func indexCaptureText(_ artifact: CaptureArtifact) {
        let image = ImageClipboardContent(
            thumbnailPath: artifact.thumbnailURL.path,
            originalPath: artifact.imageURL.path,
            sourceName: L10n.screenshotClipboardName,
            width: artifact.width,
            height: artifact.height,
            ownsCachedFiles: false
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let text = try await imageRecognitionService.recognizeText(
                    in: image,
                    languages: screenshotOCRLanguages
                )
                captureStore.updateOCRText(text, for: artifact.id)
            } catch {
                // Images without text remain valid history entries.
            }
        }
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
        let hosting = NSHostingController(rootView: makeCaptureHistoryView(theme: viewModel.settings.theme))
        captureHistoryHostingController = hosting

        if captureHistoryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.screenshotHistoryTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 720, height: 500)
            window.isReleasedWhenClosed = false
            captureHistoryWindow = window
        }

        guard let window = captureHistoryWindow else { return }
        hideLauncher()
        window.contentViewController = hosting
        centerWindowOnScreen(window, on: activeScreen())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeCaptureHistoryView(theme: AppTheme) -> CaptureHistoryView {
        CaptureHistoryView(
            store: captureStore,
            theme: theme,
            onCopy: { [weak self] artifact in
                self?.clipboardStore.writeCaptureToPasteboard(artifact)
            },
            onPin: { [weak self] artifact in
                self?.pinnedImageController.pin(artifact)
            },
            onEdit: { [weak self] artifact in
                self?.editImage(at: artifact.imageURL)
            },
            onRecognizeText: { [weak self] artifact in
                guard let self else { return }
                recognizeClipboardImage(captureImageContent(for: artifact), translate: false)
            },
            onTranslate: { [weak self] artifact in
                guard let self else { return }
                recognizeClipboardImage(captureImageContent(for: artifact), translate: true)
            },
            onScanQRCode: { [weak self] artifact in
                guard let self else { return }
                scanClipboardImageQRCode(captureImageContent(for: artifact))
            },
            onAskAI: { [weak self] artifact in
                self?.viewModel.openAIChat(
                    prompt: L10n.aiImagePrompt,
                    imagePath: artifact.imageURL.path
                )
            },
            onSendToWhiteboard: viewModel.settings.whiteboard.enabled ? { [weak self] artifact in
                self?.sendImageFileToWhiteboard(
                    at: artifact.imageURL,
                    sourceName: artifact.imageURL.lastPathComponent
                )
            } : nil,
            onDelete: { [weak self] artifact in
                guard let self else { return }
                clipboardStore.removeCaptureEntries(ids: Set([artifact.id]))
                captureStore.delete(artifact)
                viewModel.refresh()
            },
            onClear: { [weak self] in
                guard let self else { return }
                let ids = Set(captureStore.artifacts.map(\.id))
                clipboardStore.removeCaptureEntries(ids: ids)
                captureStore.clear()
                viewModel.refresh()
            }
        )
    }

    private func showLauncher() {
        createLauncherWindow()
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
        launcherWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        launcherWindow?.orderOut(nil)
        viewModel.resetForHide()
        NotificationCenter.default.post(name: .meowLauncherDidHide, object: nil)
    }

    private func toggleLauncher() {
        if launcherWindow?.isVisible == true {
            hideLauncher()
        } else {
            showLauncher()
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

    private func dismissIfClickedOutsideLauncher() {
        guard let launcherWindow, launcherWindow.isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !launcherWindow.frame.contains(mouseLocation) {
            hideLauncher()
        }
    }

    private func dismissIfClickedOutsideTranslation() {
        guard let translationWindow, translationWindow.isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !translationWindow.frame.contains(mouseLocation) {
            hideTranslationPanel()
        }
    }

    private func dismissIfClickedOutsideTextActions() {
        guard let textActionsWindow, textActionsWindow.isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !textActionsWindow.frame.contains(mouseLocation) {
            hideTextActionsPanel()
        }
    }

    private func dismissIfClickedOutsideCalendarPopover() {
        guard let popover = calendarPopover, popover.isShown else { return }
        let mouseLocation = NSEvent.mouseLocation

        if let button = statusItemService.statusItemButton,
           let buttonWindow = button.window
        {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
            if buttonRectOnScreen.contains(mouseLocation) {
                return
            }
        }

        if let popoverFrame = popover.contentViewController?.view.window?.frame,
           popoverFrame.contains(mouseLocation)
        {
            return
        }

        popover.performClose(nil)
        calendarPopover = nil
        calendarPopoverController = nil
    }

    @discardableResult
    private func dismissTranslationIfEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              translationWindow?.isVisible == true
        else { return false }

        hideTranslationPanel()
        return true
    }

    @discardableResult
    private func dismissTextActionsIfEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53,
              textActionsWindow?.isVisible == true
        else { return false }

        hideTextActionsPanel()
        return true
    }

    // MARK: - Translation panel

    private func createTextActionsWindow() {
        guard textActionsWindow == nil else { return }

        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.textActionsTitle
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        let delegate = WindowResignDelegate { [weak self] in
            self?.hideTextActionsPanel()
        }
        panel.delegate = delegate
        textActionsWindowDelegate = delegate
        textActionsWindow = panel
    }

    private func presentTextActionsHotkeyConflict(keyCode: UInt32, modifiers: UInt32) {
        let shortcut = KeyDisplayFormatter.shortcutLabel(keyCode: keyCode, modifiers: modifiers)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.textActionsHotkeyConflictTitle
        alert.informativeText = String(format: L10n.textActionsHotkeyConflictMessage, shortcut)
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func triggerTextActions() {
        let text = translationService.captureWithFallback(promptForPermission: true)
        guard !text.isEmpty else {
            presentTextActionsCaptureError(permissionDenied: translationService.axPermissionDenied)
            return
        }
        presentTextActions(for: text)
    }

    private func presentTextActionsCaptureError(permissionDenied: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.textActionsUnavailableTitle
        alert.informativeText = permissionDenied
            ? L10n.textActionsAccessibilityMessage
            : L10n.textActionsNoSelection
        if permissionDenied {
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
    }

    private func presentTextActions(for text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            presentTextActionsCaptureError(permissionDenied: false)
            return
        }

        createTextActionsWindow()
        #if MEOW_VOICE
        let canSpeak = viewModel.settings.tts.enabled
        #else
        let canSpeak = false
        #endif
        let view = TextActionsPanelView(
            text: normalized,
            theme: viewModel.settings.theme,
            canSpeak: canSpeak,
            onAction: { [weak self] action in
                self?.performTextAction(action, text: normalized)
            },
            onDismiss: { [weak self] in
                self?.hideTextActionsPanel()
            }
        )
        let hosting = NSHostingController(rootView: view)
        textActionsHostingController = hosting

        guard let panel = textActionsWindow else { return }
        panel.title = L10n.textActionsTitle
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: 520, height: 280))
        centerWindowOnScreen(panel, on: activeScreen())
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func performTextAction(_ action: TextAction, text: String) {
        hideTextActionsPanel()
        switch action {
        case .translate:
            presentTranslationPanel(text: text, axPermissionDenied: false)
        case .askAI:
            openAIChat(AIChatInitialInput(text: text))
        #if MEOW_VOICE
        case .speak:
            speechSynthesisService.synthesize(text: text, settings: viewModel.settings.tts)
        #endif
        }
    }

    private func hideTextActionsPanel() {
        textActionsWindow?.orderOut(nil)
        textActionsWindow?.contentViewController = nil
        textActionsHostingController = nil
    }

    private func createAIChatWindow() {
        guard aiChatWindow == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.aiChatTitle
        window.identifier = MeowWindowIdentifiers.aiChat
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 520)
        aiChatWindow = window
    }

    private func showAIChat(initialInput: AIChatInitialInput?) {
        createAIChatWindow()

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
        let hosting = NSHostingController(rootView: view)
        aiChatHostingController = hosting

        guard let window = aiChatWindow else { return }
        hideLauncher()
        window.contentViewController = hosting
        centerWindowOnScreen(window, on: activeScreen())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private func createTranslationWindow() {
        guard translationWindow == nil else { return }

        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 14
            contentView.layer?.masksToBounds = true
        }
        translationWindow = panel
    }

    private func triggerTranslation() {
        // Capture text while the user's app still has Accessibility focus
        // (the hotkey fires before Meow becomes active).
        let text = translationService.capture()
        presentTranslationPanel(
            text: text,
            axPermissionDenied: translationService.axPermissionDenied
        )
    }

    private func presentTranslationPanel(
        text: String,
        axPermissionDenied: Bool,
        sourceImagePath: String? = nil
    ) {
        createTranslationWindow()
        let view = AnyView(
            TranslationPanelView(
                sourceText: text,
                axPermissionDenied: axPermissionDenied,
                sourceImagePath: sourceImagePath
            ) { [weak self] in
                self?.hideTranslationPanel()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        )

        // Always create a fresh hosting controller so SwiftUI @State is reset
        // for every new translation (config must go nil → non-nil to re-trigger
        // translationTask, which requires a fresh view lifecycle).
        let hosting = NSHostingController(rootView: view)
        translationHostingController = hosting

        guard let panel = translationWindow else { return }
        panel.contentViewController = hosting

        panel.setContentSize(estimatedTranslationPanelSize(for: text))
        centerWindowOnScreen(panel, on: activeScreen())
        panel.orderFront(nil)   // non-activating — user's app keeps focus
    }

    private func recognizeClipboardImage(_ image: ImageClipboardContent, translate: Bool) {
        hideLauncher()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let text = try await imageRecognitionService.recognizeText(
                    in: image,
                    languages: screenshotOCRLanguages
                )
                if translate {
                    presentTranslationPanel(
                        text: text,
                        axPermissionDenied: false,
                        sourceImagePath: image.originalPath ?? image.thumbnailPath
                    )
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    let alert = NSAlert()
                    alert.messageText = L10n.screenshotOCRCopiedTitle
                    alert.informativeText = L10n.screenshotOCRCopiedMessage
                    alert.addButton(withTitle: L10n.actionOK)
                    alert.runModal()
                }
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.screenshotOCRErrorTitle
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L10n.actionOK)
                alert.runModal()
            }
        }
    }

    private func scanClipboardImageQRCode(_ image: ImageClipboardContent) {
        hideLauncher()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await imageRecognitionService.detectQRCode(in: image)
                if payload.lowercased().hasPrefix("otpauth://") {
                    presentOTPAuthImport(payload)
                } else {
                    presentQRCodePayload(payload)
                }
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.screenshotQRErrorTitle
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L10n.actionOK)
                alert.runModal()
            }
        }
    }

    private var screenshotOCRLanguages: [String] {
        viewModel.settings.screenshot.ocrLanguages.map(\.visionIdentifier)
    }

    private func editClipboardImage(_ image: ImageClipboardContent) {
        let path = image.originalPath ?? image.thumbnailPath
        editImage(at: URL(fileURLWithPath: path))
    }

    private func openClipboardImage(_ image: ImageClipboardContent) {
        hideLauncher()
        let path = image.originalPath ?? image.thumbnailPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func saveClipboardImageAs(_ imageContent: ImageClipboardContent) {
        hideLauncher()
        let path = imageContent.originalPath ?? imageContent.thumbnailPath
        guard let image = NSImage(contentsOfFile: path) else {
            presentScreenshotError(ImageRecognitionError.imageUnavailable)
            return
        }

        let sourceExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = sourceExtension == "jpg" || sourceExtension == "jpeg"
            ? "\(imageContent.sourceName).jpg"
            : "\(imageContent.sourceName).png"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let fileExtension = destination.pathExtension.lowercased()
            let data: Data?
            if fileExtension == "jpg" || fileExtension == "jpeg",
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            {
                data = NSBitmapImageRep(cgImage: cgImage).representation(
                    using: .jpeg,
                    properties: [.compressionFactor: 0.9]
                )
            } else {
                data = image.pngData()
            }
            guard let data else {
                throw CaptureStoreError.imageEncodingFailed
            }
            try data.write(to: destination, options: .atomic)
        } catch {
            presentScreenshotError(error)
        }
    }

    private func editImage(at url: URL) {
        hideLauncher()
        Task { @MainActor [weak self] in
            guard let self,
                  let image = NSImage(contentsOf: url),
                  let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let edited = await captureEditorController.present(source: source)
            else { return }

            do {
                let artifact = try processCapturedImage(edited, kind: .edited)
                showPostCaptureActionsIfNeeded(for: artifact)
            } catch {
                presentScreenshotError(error)
            }
        }
    }

    private func showPostCaptureActionsIfNeeded(for artifact: CaptureArtifact) {
        let settings = viewModel.settings.screenshot
        guard settings.showPostCaptureActions else { return }
        postCaptureActionsController.show(
            artifact: artifact,
            duration: settings.postCaptureActionDuration,
            includesUpload: viewModel.settings.fileHosting.s3.isEnabled,
            includesWhiteboard: viewModel.settings.whiteboard.enabled
        ) { [weak self] action, artifact in
            self?.handlePostCaptureAction(action, artifact: artifact)
        }
    }

    private func handlePostCaptureAction(
        _ action: PostCaptureAction,
        artifact: CaptureArtifact
    ) {
        let imageContent = captureImageContent(for: artifact)
        switch action {
        case .copy:
            clipboardStore.writeCaptureToPasteboard(artifact)
        case .save:
            do {
                guard let image = NSImage(contentsOf: artifact.imageURL),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else {
                    throw CaptureStoreError.imageEncodingFailed
                }
                _ = try captureStore.saveExternal(
                    image: cgImage,
                    settings: viewModel.settings.screenshot
                )
            } catch {
                presentScreenshotError(error)
            }
        case .edit:
            editImage(at: artifact.imageURL)
        case .pin:
            pinnedImageController.pin(artifact)
        case .recognizeText:
            recognizeClipboardImage(imageContent, translate: false)
        case .translate:
            recognizeClipboardImage(imageContent, translate: true)
        case .askAI:
            viewModel.openAIChat(
                prompt: L10n.aiImagePrompt,
                imagePath: artifact.imageURL.path
            )
        case .whiteboard:
            sendImageFileToWhiteboard(
                at: artifact.imageURL,
                sourceName: artifact.imageURL.lastPathComponent
            )
        case .upload:
            upload(fileURL: artifact.imageURL)
        }
    }

    private func applyUploadHotkey(_ settings: FileHostSettings) {
        guard settings.s3.isEnabled,
              settings.uploadHotkeyKeyCode != 0,
              settings.uploadHotkeyModifiers != 0
        else {
            hotkeyService.unregisterUploadHotkey()
            lastRegisteredUploadHotkey = nil
            return
        }
        let result = hotkeyService.registerUploadHotkey(
            keyCode: settings.uploadHotkeyKeyCode,
            modifiers: settings.uploadHotkeyModifiers
        ) { [weak self] in
            self?.triggerScreenshot(mode: .region, uploadAfterCapture: true)
        }
        handleHotkeyRegistrationResult(
            result,
            name: "upload screenshot",
            keyCode: settings.uploadHotkeyKeyCode,
            modifiers: settings.uploadHotkeyModifiers,
            previous: lastRegisteredUploadHotkey
        ) { [weak self] keyCode, modifiers in
            self?.viewModel.settings.fileHosting.uploadHotkeyKeyCode = keyCode
            self?.viewModel.settings.fileHosting.uploadHotkeyModifiers = modifiers
        } onSuccess: { [weak self] in
            self?.lastRegisteredUploadHotkey = (settings.uploadHotkeyKeyCode, settings.uploadHotkeyModifiers)
        }
    }

    private func upload(fileURL: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await fileUploadService.upload(fileURL: fileURL)
            } catch {
                presentUploadError(error)
            }
        }
    }

    private func uploadFromClipboard() {
        guard viewModel.settings.fileHosting.s3.isEnabled else {
            presentUploadError(UploadError.notConfigured)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await fileUploadService.uploadFromClipboard()
            } catch {
                presentUploadError(error)
            }
        }
    }

    private func presentUploadError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.uploadErrorTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    private func captureImageContent(for artifact: CaptureArtifact) -> ImageClipboardContent {
        ImageClipboardContent(
            thumbnailPath: artifact.thumbnailURL.path,
            originalPath: artifact.imageURL.path,
            sourceName: L10n.screenshotClipboardName,
            width: artifact.width,
            height: artifact.height,
            ownsCachedFiles: false
        )
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
        translationWindow?.orderOut(nil)
    }

    private func estimatedTranslationPanelSize(for text: String) -> NSSize {
        let width: CGFloat = 560

        // Use both explicit newlines and rough wrapped-line estimation.
        let newlineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let wrappedLines = max(0, text.count / 48)
        let estimatedLines = max(1, newlineCount + wrappedLines)

        let minHeight: CGFloat = 310
        let maxHeight: CGFloat = 560
        let estimatedHeight = CGFloat(estimatedLines) * 24 + 250
        let height = min(max(estimatedHeight, minHeight), maxHeight)

        return NSSize(width: width, height: height)
    }

    private func showPreferences(section: PreferenceSection? = nil, animated: Bool = true) {
        if let section {
            preferencesNavigation.selectedSection = section
        }

        let isFirstPresentation = preferencesWindow == nil
        if preferencesWindow == nil {
            let makeCaptureHistoryView: (AppTheme) -> CaptureHistoryView = { [weak self] theme in
                guard let self else {
                    return CaptureHistoryView(
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
                }
                return self.makeCaptureHistoryView(theme: theme)
            }
            let recordingHistoryContext = RecordingHistoryContext(
                store: recordingStore,
                onDelete: { [weak self] artifact in
                    self?.recordingStore.delete(artifact)
                },
                onTrim: { [weak self] artifact in
                    self?.showRecordingTrimmer(for: artifact.fileURL)
                }
            )
            #if MEOW_VOICE
            let prefs = PreferencesView(
                viewModel: viewModel,
                navigation: preferencesNavigation,
                aiChatHistoryStore: aiChatHistoryStore,
                keystrokeVisualizerService: keystrokeVisualizerService,
                authenticatorService: authenticatorService,
                healthReminderService: healthReminderService,
                speechModelStore: speechModelStore,
                speechHistoryStore: speechHistoryStore,
                speechRecognitionService: speechRecognitionService,
                ttsModelStore: ttsModelStore,
                speechSynthesisService: speechSynthesisService,
                fileUploadService: fileUploadService,
                makeCaptureHistoryView: makeCaptureHistoryView,
                recordingHistoryContext: recordingHistoryContext
            )
            #else
            let prefs = PreferencesView(
                viewModel: viewModel,
                navigation: preferencesNavigation,
                aiChatHistoryStore: aiChatHistoryStore,
                keystrokeVisualizerService: keystrokeVisualizerService,
                authenticatorService: authenticatorService,
                healthReminderService: healthReminderService,
                fileUploadService: fileUploadService,
                makeCaptureHistoryView: makeCaptureHistoryView,
                recordingHistoryContext: recordingHistoryContext
            )
            #endif
            let hosting = NSHostingController(rootView: prefs)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.setContentSize(NSSize(width: 840, height: 560))
            centerWindowOnScreen(window, on: activeScreen())
            window.title = L10n.windowPrefsTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .preference
            window.minSize = NSSize(width: 820, height: 520)
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            preferencesWindow = window
        }

        guard let window = preferencesWindow else { return }
        hideLauncher()
        window.title = L10n.windowPrefsTitle

        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: false)
            return
        }

        // Recenter when opening from hidden state so it doesn't stick near the top
        // after display changes or previous system-driven position adjustments.
        centerWindowOnScreen(window, on: activeScreen())

        if animated {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                window.animator().alphaValue = 1
            }
        } else {
            window.makeKeyAndOrderFront(nil)
        }

        if isFirstPresentation {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.centerWindowOnScreen(window, on: self.activeScreen())
            }
        }

        NSApp.activate(ignoringOtherApps: false)
    }

    func openPreferencesFromCommand() {
        showPreferences(animated: true)
    }

    private func showCalendarPopover() {
        if let popover = calendarPopover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let initialSize = NSSize(width: 320, height: 314)
        popover.contentSize = initialSize

        let view = makeCalendarPopoverView(for: popover)
        let hosting = NSHostingController(rootView: view)
        popover.contentViewController = hosting

        guard let button = statusItemService.statusItemButton else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        calendarPopover = popover
        calendarPopoverController = hosting
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
            onContentSizeChanged: { [weak self, weak popover] size in
                (popover ?? self?.calendarPopover)?.contentSize = size
            },
            refreshToken: calendarRefreshToken
        )
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func centerWindowOnScreen(_ window: NSWindow, on targetScreen: NSScreen? = nil) {
        let targetScreen = targetScreen ?? activeScreen()
        guard let screenFrame = targetScreen?.frame else {
            window.center()
            return
        }

        let x = screenFrame.origin.x + (screenFrame.width - window.frame.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - window.frame.height) / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
