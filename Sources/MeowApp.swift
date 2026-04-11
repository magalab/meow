import AppKit
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
                .keyboardShortcut(",", modifiers: [.command])
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

    private var launcherWindow: LauncherPanel?
    private var preferencesWindow: NSWindow?
    private var viewModel: LauncherViewModel!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = LauncherViewModel(
            settingsStore: settingsStore,
            discoveryService: discoveryService,
            launchHistoryStore: launchHistoryStore
        )
        viewModel.onOpenPreferences = { [weak self] in
            self?.showPreferences()
        }
        viewModel.onSettingsChanged = { [weak self] settings in
            self?.apply(settings: settings)
        }
        viewModel.load()

        let initial = settingsStore.load()
        apply(settings: initial)

        setupStatusItem()
        createLauncherWindow()
        setupOutsideClickDismissMonitor()
        showLauncher()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func createLauncherWindow() {
        let content = LauncherView(viewModel: viewModel) { [weak self] in
            self?.hideLauncher()
        }
        let hosting = NSHostingController(rootView: content)

        let window = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = true
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 20
            contentView.layer?.masksToBounds = true
        }
        launcherWindow = window
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
        // Apply language first so all subsequent L10n calls use the correct bundle.
        LanguageManager.shared.apply(settings.language)
        statusItemService.updateL10n()
        viewModel?.refresh()

        let wasLauncherVisible = launcherWindow?.isVisible == true
        let wasPreferencesVisible = preferencesWindow?.isVisible == true
        
        // Recreate launcher window to reflect language changes in NSHostingController.
        if wasLauncherVisible {
            launcherWindow?.orderOut(nil)
            launcherWindow = nil
            createLauncherWindow()
            showLauncher()
        }
        
        // Close and recreate preferences window when language changes to reflect new strings.
        if wasPreferencesVisible {
            preferencesWindow?.close()
            preferencesWindow = nil
        }

        dockService.apply(showDockIcon: settings.showDockIcon)
        statusItemService.setVisible(settings.showStatusItem)
        statusItemService.updateToggleStates(settings)
        autoLaunchService.apply(enabled: settings.autoLaunch)
        hotkeyService.registerToggleHotkey(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        ) { [weak self] in
            self?.toggleLauncher()
        }

        // Reopen preferences window after recreating it.
        if wasPreferencesVisible {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences(animated: false)
            }
        }
    }

    private func showLauncher() {
        launcherWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideLauncher() {
        launcherWindow?.orderOut(nil)
    }

    private func toggleLauncher() {
        if launcherWindow?.isVisible == true {
            hideLauncher()
        } else {
            showLauncher()
        }
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
    }

    private func dismissIfClickedOutsideLauncher() {
        guard let launcherWindow, launcherWindow.isVisible else { return }
        let mouseLocation = NSEvent.mouseLocation
        if !launcherWindow.frame.contains(mouseLocation) {
            hideLauncher()
        }
    }

    private func showPreferences(animated: Bool = true) {
        if preferencesWindow == nil {
            let prefs = PreferencesView(viewModel: viewModel)
            let hosting = NSHostingController(rootView: prefs)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = L10n.windowPrefsTitle
            window.minSize = NSSize(width: 620, height: 420)
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            preferencesWindow = window
        }

        guard let window = preferencesWindow else { return }
        window.title = L10n.windowPrefsTitle

        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPreferencesFromCommand() {
        showPreferences(animated: true)
    }
}
