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
    struct EventMonitorDriver {
        let addGlobal: @MainActor (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
        let addLocal: @MainActor (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
        let remove: @MainActor (Any) -> Void

        static let appKit = EventMonitorDriver(
            addGlobal: { mask, handler in
                NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
            },
            addLocal: { mask, handler in
                NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
            },
            remove: { monitor in
                NSEvent.removeMonitor(monitor)
            }
        )
    }

    struct EventMonitorActions {
        let dismissLauncher: @MainActor () -> Void
        let dismissTranslation: @MainActor () -> Void
        let dismissTextActions: @MainActor () -> Void
        let dismissCalendarPopover: @MainActor () -> Void
        let statusItemButton: @MainActor () -> NSButton?
        let cancelSpeechIfActive: @MainActor () -> Bool
        let showPreferences: @MainActor () -> Void
    }

    private let defaultLauncherWidth: CGFloat = 560
    private var launcherWindow: LauncherPanel?
    private var hasLaidOutLauncher = false
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
    private var calendarPopoverController: NSHostingController<LocalizedRootView<CalendarPopoverView>>?
    private var eventMonitorActions: EventMonitorActions?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var eventMonitorsInstalled = false
    private let eventMonitorDriver: EventMonitorDriver

    init(eventMonitorDriver: EventMonitorDriver = .appKit) {
        self.eventMonitorDriver = eventMonitorDriver
    }

    func installEventMonitors(actions: EventMonitorActions) {
        guard !eventMonitorsInstalled else { return }
        eventMonitorActions = actions

        globalMouseMonitor = eventMonitorDriver.addGlobal([.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            self?.dismissWindowsClickedOutside()
        }
        localMouseMonitor = eventMonitorDriver.addLocal([.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            self?.dismissWindowsClickedOutside()
            return event
        }
        globalKeyMonitor = eventMonitorDriver.addGlobal([.keyDown]) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 {
                _ = eventMonitorActions?.cancelSpeechIfActive()
            }
            _ = dismissTranslationIfEscape(event)
            _ = dismissTextActionsIfEscape(event)
        }
        localKeyMonitor = eventMonitorDriver.addLocal([.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                var handled = eventMonitorActions?.cancelSpeechIfActive() ?? false
                if dismissTranslationIfEscape(event) { handled = true }
                if dismissTextActionsIfEscape(event) { handled = true }
                if handled { return nil }
            }
            if dismissTranslationIfEscape(event) { return nil }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command), event.charactersIgnoringModifiers == "," {
                eventMonitorActions?.showPreferences()
                return nil
            }
            return event
        }
        eventMonitorsInstalled = true
    }

    func removeEventMonitors() {
        for monitor in [globalMouseMonitor, localMouseMonitor, globalKeyMonitor, localKeyMonitor].compactMap({ $0 }) {
            eventMonitorDriver.remove(monitor)
        }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
        eventMonitorActions = nil
        eventMonitorsInstalled = false
    }

    private func dismissWindowsClickedOutside() {
        dismissIfClickedOutsideLauncher()
        dismissIfClickedOutsideTranslation()
        dismissIfClickedOutsideTextActions()
        dismissIfClickedOutsideCalendarPopover()
    }

    private func dismissIfClickedOutsideLauncher() {
        guard isLauncherVisible, let frame = launcherFrame(), !frame.contains(NSEvent.mouseLocation) else { return }
        eventMonitorActions?.dismissLauncher()
    }

    private func dismissIfClickedOutsideTranslation() {
        guard isTranslationVisible, let frame = translationFrame(), !frame.contains(NSEvent.mouseLocation) else { return }
        eventMonitorActions?.dismissTranslation()
    }

    private func dismissIfClickedOutsideTextActions() {
        guard isTextActionsVisible, let frame = textActionsFrame(), !frame.contains(NSEvent.mouseLocation) else { return }
        eventMonitorActions?.dismissTextActions()
    }

    private func dismissIfClickedOutsideCalendarPopover() {
        guard isCalendarPopoverShown,
              !calendarPopoverContains(mouseLocation: NSEvent.mouseLocation,
                                       statusButton: eventMonitorActions?.statusItemButton())
        else { return }
        eventMonitorActions?.dismissCalendarPopover()
    }

    private func dismissTranslationIfEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, isTranslationVisible else { return false }
        eventMonitorActions?.dismissTranslation()
        return true
    }

    private func dismissTextActionsIfEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53, isTextActionsVisible else { return false }
        eventMonitorActions?.dismissTextActions()
        return true
    }

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
            contentRect: NSRect(x: 0, y: 0, width: defaultLauncherWidth, height: 540),
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
            contentView.layer?.cornerRadius = 8
            contentView.layer?.masksToBounds = true
        }
        launcherWindow = window
    }

    func showLauncher(makeContent: () -> NSViewController) {
        createLauncherWindowIfNeeded()
        if launcherWindow?.contentViewController == nil {
            launcherWindow?.contentViewController = makeContent()
        }
        if let launcherWindow {
            let contentSize = launcherWindow.contentRect(forFrameRect: launcherWindow.frame).size
            if contentSize.width < 520 {
                launcherWindow.setContentSize(
                    NSSize(width: defaultLauncherWidth, height: contentSize.height)
                )
            }
            launcherWindow.contentView?.layoutSubtreeIfNeeded()
            positionLauncher(launcherWindow)
        }
        launcherWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setLauncherHeight(_ height: CGFloat) {
        createLauncherWindowIfNeeded()
        guard let launcherWindow else { return }
        let currentSize = launcherWindow.contentRect(forFrameRect: launcherWindow.frame).size
        let launcherWidth = max(currentSize.width, defaultLauncherWidth)
        guard abs(currentSize.height - height) > 0.5 else {
            if !hasLaidOutLauncher {
                positionLauncher(launcherWindow)
                hasLaidOutLauncher = true
            }
            return
        }

        if !hasLaidOutLauncher {
            launcherWindow.setContentSize(NSSize(width: launcherWidth, height: height))
            positionLauncher(launcherWindow)
            hasLaidOutLauncher = true
            return
        }

        let topEdge = launcherWindow.frame.maxY
        launcherWindow.setContentSize(NSSize(width: launcherWidth, height: height))
        setLauncherOrigin(
            NSPoint(x: launcherWindow.frame.origin.x, y: topEdge - launcherWindow.frame.height),
            for: launcherWindow
        )
    }

    private func setLauncherOrigin(_ origin: NSPoint, for window: NSWindow) {
        guard let screen = activeScreen() else {
            window.setFrameOrigin(origin)
            return
        }
        let visibleFrame = screen.visibleFrame
        let maximumOrigin = NSPoint(
            x: max(visibleFrame.minX, visibleFrame.maxX - window.frame.width),
            y: max(visibleFrame.minY, visibleFrame.maxY - window.frame.height)
        )
        window.setFrameOrigin(
            NSPoint(
                x: min(max(origin.x, visibleFrame.minX), maximumOrigin.x),
                y: min(max(origin.y, visibleFrame.minY), maximumOrigin.y)
            )
        )
    }

    private func positionLauncher(_ window: NSWindow) {
        guard let screen = activeScreen() else {
            center(window)
            return
        }
        let visibleFrame = screen.visibleFrame
        let targetCenter = NSPoint(
            x: visibleFrame.midX,
            y: visibleFrame.minY + visibleFrame.height * 0.58
        )
        let proposedOrigin = NSPoint(
            x: targetCenter.x - window.frame.width / 2,
            y: targetCenter.y - window.frame.height / 2
        )
        setLauncherOrigin(proposedOrigin, for: window)
    }

    func refreshLocalizedWindowTitles() {
        textActionsWindow?.title = L10n.textActionsTitle
        aiChatWindow?.title = L10n.aiChatTitle
        preferencesWindow?.title = L10n.windowPrefsTitle
        captureHistoryWindow?.title = L10n.screenshotHistoryTitle
        recordingPreviewWindow?.title = L10n.recordingPreviewTitle
        recordingHistoryWindow?.title = L10n.recordingHistoryTitle
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.minSize = NSSize(width: 720, height: 540)
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
        let content = contentView(popover)
        popover.contentViewController = NSHostingController(
            rootView: LocalizedRootView { content }
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        calendarPopover = popover
        calendarPopoverController = popover.contentViewController as? NSHostingController<LocalizedRootView<CalendarPopoverView>>
    }

    func refreshCalendar(contentView: (NSPopover?) -> CalendarPopoverView) {
        guard let calendarPopover,
              calendarPopover.isShown,
              let calendarPopoverController
        else { return }
        let content = contentView(calendarPopover)
        calendarPopoverController.rootView = LocalizedRootView { content }
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
