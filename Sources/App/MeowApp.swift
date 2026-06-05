import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

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
    private let clipboardStore = ClipboardStore()
    private let preferencesNavigation = PreferencesNavigationState()
    private let aiChatHistoryStore = AIChatHistoryStore()

    private let translationService = TranslationService()

    private var launcherWindow: LauncherPanel?
    private var launcherHostingController: NSHostingController<LauncherView>?
    private var translationWindow: LauncherPanel?
    private var translationHostingController: NSHostingController<AnyView>?
    private var aiChatWindow: NSWindow?
    private var aiChatHostingController: NSHostingController<AnyView>?
    private var preferencesWindow: NSWindow?
    private var viewModel: LauncherViewModel!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var appliedLanguage: AppLanguage?
    private var lastRegisteredToggleHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var lastRegisteredTranslateHotkey: (keyCode: UInt32, modifiers: UInt32)?
    private var clipboardMonitoringEnabled = false
    private var calendarPopover: NSPopover?
    private var calendarPopoverController: NSHostingController<CalendarPopoverView>?

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
        viewModel.onOpenAIChat = { [weak self] prompt in
            self?.showAIChat(initialPrompt: prompt)
        }
        viewModel.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
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

        setupStatusItem()
        let initial = settingsStore.load()
        dockIconService.start(style: initial.dockIconStyle)
        apply(settings: initial)
        createLauncherWindow()
        createTranslationWindow()
        createAIChatWindow()
        setupOutsideClickDismissMonitor()
    }

    func applicationWillTerminate(_: Notification) {
        hotkeyService.unregister()
        keystrokeVisualizerService.stop()
        clipboardStore.stopMonitoring()
        dockIconService.stop()
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

    func applicationDidBecomeActive(_: Notification) {
        keystrokeVisualizerService.retryAfterPermissionChange()
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
        aiChatHistoryStore.setPersistenceEnabled(settings.ai.chatHistoryEnabled)
        keystrokeVisualizerService.apply(settings: settings)
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
            DispatchQueue.main.async {
                restore(previous.keyCode, previous.modifiers)
            }
        }
    }

    private func showLauncher() {
        // Keep app list fresh so newly installed apps appear without restarting Meow.
        if !viewModel.refreshInstalledApps() {
            viewModel.refresh()
        }
        launcherWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

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
            self?.dismissIfClickedOutsideCalendarPopover()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            self?.dismissIfClickedOutsideLauncher()
            self?.dismissIfClickedOutsideTranslation()
            self?.dismissIfClickedOutsideCalendarPopover()
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.dismissTranslationIfEscape(event)
        }

        // Use a single app-level shortcut path for Cmd+, because command routing can
        // be unreliable when the launcher is a nonactivating panel.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
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

    // MARK: - Translation panel

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

    private func showAIChat(initialPrompt: String?) {
        createAIChatWindow()

        let view = AnyView(
            AIChatPanelView(
                viewModel: viewModel,
                initialPrompt: initialPrompt,
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

        let view = AnyView(
            TranslationPanelView(
                sourceText: text,
                axPermissionDenied: translationService.axPermissionDenied
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
            let prefs = PreferencesView(
                viewModel: viewModel,
                navigation: preferencesNavigation,
                aiChatHistoryStore: aiChatHistoryStore,
                keystrokeVisualizerService: keystrokeVisualizerService
            )
            let hosting = NSHostingController(rootView: prefs)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 448),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.setContentSize(NSSize(width: 680, height: 448))
            centerWindowOnScreen(window, on: activeScreen())
            window.title = L10n.windowPrefsTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .preference
            window.minSize = NSSize(width: 680, height: 420)
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.level = .modalPanel
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            preferencesWindow = window
        }

        guard let window = preferencesWindow else { return }
        hideLauncher()
        window.title = L10n.windowPrefsTitle

        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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

        NSApp.activate(ignoringOtherApps: true)
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

        let view = CalendarPopoverView(theme: viewModel.settings.theme) { [weak popover] size in
            popover?.contentSize = size
        }
        let hosting = NSHostingController(rootView: view)
        popover.contentViewController = hosting

        guard let button = statusItemService.statusItemButton else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        calendarPopover = popover
        calendarPopoverController = hosting
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
