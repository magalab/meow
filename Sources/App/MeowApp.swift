import AppKit
import ApplicationServices
import SwiftUI

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
    private let statusItemService = StatusItemService()
    private let discoveryService = AppDiscoveryService()
    private let launchHistoryStore = LaunchHistoryStore()
    private let autoLaunchService = AutoLaunchService()
    private let hotkeyService = HotkeyService()
    private let clipboardStore = ClipboardStore()

    private var launcherWindow: LauncherPanel?
    private var launcherHostingController: NSHostingController<LauncherView>?
    private var preferencesWindow: NSWindow?
    private var viewModel: LauncherViewModel!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var appliedLanguage: AppLanguage?
    private var clipboardMonitoringEnabled = false

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
        viewModel.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
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
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, _ in }
            }
        }
        viewModel.load()

        setupStatusItem()
        let initial = settingsStore.load()
        apply(settings: initial)
        createLauncherWindow()
        setupOutsideClickDismissMonitor()
    }

    func applicationWillTerminate(_: Notification) {
        hotkeyService.unregister()
        clipboardStore.stopMonitoring()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
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
    }

    private func apply(settings: AppSettings) {
        let languageChanged = appliedLanguage != settings.language
        if languageChanged {
            LanguageManager.shared.apply(settings.language)
            statusItemService.updateL10n()
            viewModel?.refresh()
            preferencesWindow?.title = L10n.windowPrefsTitle
            appliedLanguage = settings.language
        }

        dockService.apply(showDockIcon: settings.showDockIcon)
        statusItemService.setVisible(settings.showStatusItem)
        statusItemService.updateToggleStates(settings)
        let actualAutoLaunchEnabled = autoLaunchService.apply(enabled: settings.autoLaunch)
        hotkeyService.registerToggleHotkey(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        ) { [weak self] in
            self?.toggleLauncher()
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
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            self?.dismissIfClickedOutsideLauncher()
            return event
        }

        // Use a single app-level shortcut path for Cmd+, because command routing can
        // be unreliable when the launcher is a nonactivating panel.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
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

    private func showPreferences(animated: Bool = true) {
        let isFirstPresentation = preferencesWindow == nil
        if preferencesWindow == nil {
            let prefs = PreferencesView(viewModel: viewModel)
            let hosting = NSHostingController(rootView: prefs)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 448),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.setContentSize(NSSize(width: 620, height: 448))
            centerWindowOnScreen(window, on: activeScreen())
            window.title = L10n.windowPrefsTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .preference
            window.minSize = NSSize(width: 620, height: 420)
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
