import AppKit
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

@MainActor
final class AppWindowCoordinator {
    private var launcherWindow: LauncherPanel?
    private var translationWindow: LauncherPanel?
    private var textActionsWindow: LauncherPanel?
    private var textActionsWindowDelegate: WindowResignDelegate?
    private var aiChatWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var captureHistoryWindow: NSWindow?
    private var recordingHistoryWindow: NSWindow?
    private var recordingControlWindow: NSPanel?
    private var recordingPreviewWindow: NSPanel?
    private var recordingTrimmerWindows: [URL: NSWindow] = [:]
    private var recordingTrimmerDelegates: [URL: WindowCloseDelegate] = [:]
    private var calendarPopover: NSPopover?
    private var calendarPopoverController: NSHostingController<CalendarPopoverView>?

    func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    func center(_ window: NSWindow, on targetScreen: NSScreen? = nil) {
        let targetScreen = targetScreen ?? activeScreen()
        guard let screenFrame = targetScreen?.frame else {
            window.center()
            return
        }

        let x = screenFrame.origin.x + (screenFrame.width - window.frame.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - window.frame.height) / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    var isLauncherVisible: Bool {
        launcherWindow?.isVisible == true
    }

    var isTranslationVisible: Bool {
        translationWindow?.isVisible == true
    }

    var isTextActionsVisible: Bool {
        textActionsWindow?.isVisible == true
    }

    var isCalendarPopoverShown: Bool {
        calendarPopover?.isShown == true
    }

    func launcherFrame() -> NSRect? {
        launcherWindow?.frame
    }

    func translationFrame() -> NSRect? {
        translationWindow?.frame
    }

    func textActionsFrame() -> NSRect? {
        textActionsWindow?.frame
    }

    func calendarPopoverFrame() -> NSRect? {
        calendarPopover?.contentViewController?.view.window?.frame
    }

    func createLauncherWindowIfNeeded() {
        guard launcherWindow == nil else { return }

        let window = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        center(window)
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
    }

    func showLauncher(makeContent: () -> NSViewController) {
        createLauncherWindowIfNeeded()
        if launcherWindow?.contentViewController == nil {
            launcherWindow?.contentViewController = makeContent()
        }
        launcherWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLauncher() {
        launcherWindow?.orderOut(nil)
    }

    func showTranslation(contentViewController: NSViewController, size: NSSize) {
        createTranslationWindowIfNeeded()
        translationWindow?.contentViewController = contentViewController
        translationWindow?.setContentSize(size)
        if let translationWindow {
            center(translationWindow, on: activeScreen())
            translationWindow.orderFront(nil)
        }
    }

    func hideTranslation() {
        translationWindow?.orderOut(nil)
    }

    func createTranslationWindowIfNeeded() {
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

    func showTextActions(contentViewController: NSViewController, onResign: @escaping () -> Void) {
        createTextActionsWindowIfNeeded(onResign: onResign)
        textActionsWindow?.title = L10n.textActionsTitle
        textActionsWindow?.contentViewController = contentViewController
        textActionsWindow?.setContentSize(NSSize(width: 520, height: 280))
        if let textActionsWindow {
            center(textActionsWindow, on: activeScreen())
            textActionsWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideTextActions() {
        textActionsWindow?.orderOut(nil)
        textActionsWindow?.contentViewController = nil
    }

    private func createTextActionsWindowIfNeeded(onResign: @escaping () -> Void) {
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
        let delegate = WindowResignDelegate(onResign: onResign)
        panel.delegate = delegate
        textActionsWindowDelegate = delegate
        textActionsWindow = panel
    }

    func showAIChat(contentViewController: NSViewController) {
        createAIChatWindowIfNeeded()
        aiChatWindow?.contentViewController = contentViewController
        if let aiChatWindow {
            center(aiChatWindow, on: activeScreen())
            aiChatWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createAIChatWindowIfNeeded() {
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

    func updatePreferencesTitle(_ title: String) {
        preferencesWindow?.title = title
    }

    func showPreferences(
        title: String,
        animated: Bool,
        makeContent: () -> NSViewController
    ) {
        let isFirstPresentation = preferencesWindow == nil
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.setContentSize(NSSize(width: 840, height: 560))
            center(window, on: activeScreen())
            window.title = title
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .preference
            window.minSize = NSSize(width: 820, height: 520)
            window.contentViewController = makeContent()
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            preferencesWindow = window
        }

        guard let window = preferencesWindow else { return }
        window.title = title
        NSApp.activate(ignoringOtherApps: true)

        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        center(window, on: activeScreen())
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
                self.center(window, on: self.activeScreen())
            }
        }
    }

    func showCaptureHistory(contentViewController: NSViewController, title: String) {
        if captureHistoryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 720, height: 500)
            window.isReleasedWhenClosed = false
            captureHistoryWindow = window
        }

        guard let window = captureHistoryWindow else { return }
        window.contentViewController = contentViewController
        center(window, on: activeScreen())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showRecordingControl(contentView: NSView) {
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
            recordingControlWindow = panel
        }

        guard let panel = recordingControlWindow else { return }
        if panel.contentView !== contentView {
            panel.contentView = contentView
        }
        if let screen = activeScreen() {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.maxY - panel.frame.height - 16
            ))
        }
        panel.orderFrontRegardless()
    }

    func hideRecordingControl() {
        recordingControlWindow?.orderOut(nil)
    }

    func showRecordingPreview(
        size: NSSize,
        makeContent: () -> NSViewController
    ) {
        recordingPreviewWindow?.orderOut(nil)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.contentViewController = makeContent()
        recordingPreviewWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideRecordingPreview() {
        recordingPreviewWindow?.orderOut(nil)
    }

    func showRecordingHistory(contentViewController: NSViewController, title: String) {
        if recordingHistoryWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            recordingHistoryWindow = window
        }

        guard let window = recordingHistoryWindow else { return }
        center(window)
        window.contentViewController = contentViewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showRecordingTrimmer(
        for url: URL,
        contentViewController: NSViewController
    ) {
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
        window.contentViewController = contentViewController
        window.isReleasedWhenClosed = false
        let delegate = WindowCloseDelegate { [weak self] in
            self?.recordingTrimmerWindows[url] = nil
            self?.recordingTrimmerDelegates[url] = nil
        }
        window.delegate = delegate
        center(window)
        recordingTrimmerWindows[url] = window
        recordingTrimmerDelegates[url] = delegate
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleCalendarPopover(
        contentView: (NSPopover) -> CalendarPopoverView,
        relativeTo button: NSButton
    ) {
        if let calendarPopover, calendarPopover.isShown {
            calendarPopover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 314)
        popover.contentViewController = NSHostingController(rootView: contentView(popover))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        calendarPopover = popover
        calendarPopoverController = popover.contentViewController as? NSHostingController<CalendarPopoverView>
    }

    func refreshCalendar(contentView: (NSPopover?) -> CalendarPopoverView) {
        guard let calendarPopover,
              calendarPopover.isShown,
              let calendarPopoverController
        else { return }
        calendarPopoverController.rootView = contentView(calendarPopover)
    }

    func dismissCalendarPopover() {
        calendarPopover?.performClose(nil)
        calendarPopover = nil
        calendarPopoverController = nil
    }

    func calendarPopoverContains(
        mouseLocation: NSPoint,
        statusButton: NSButton?
    ) -> Bool {
        if let button = statusButton,
           let buttonWindow = button.window
        {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
            if buttonRectOnScreen.contains(mouseLocation) {
                return true
            }
        }

        return calendarPopoverFrame()?.contains(mouseLocation) == true
    }
}
