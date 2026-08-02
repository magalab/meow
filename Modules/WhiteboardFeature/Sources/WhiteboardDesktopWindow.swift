import AppKit

@MainActor
final class WhiteboardDesktopWindow: NSWindow {
    private static let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
    )

    private(set) var isEditingBoard = false

    override var canBecomeKey: Bool { isEditingBoard }
    override var canBecomeMain: Bool { isEditingBoard }

    init(screen: NSScreen, applicationName: String) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.desktopLevel
        ignoresMouseEvents = true
        collectionBehavior = [.stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        title = WhiteboardLocalization.format("whiteboard.window.title", applicationName)
    }

    func setEditing(_ editing: Bool) {
        isEditingBoard = editing
        ignoresMouseEvents = !editing
        level = editing ? .normal : Self.desktopLevel
        if editing {
            collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self] in
                self?.collectionBehavior = [.stationary, .ignoresCycle]
            }
        } else {
            resignKey()
            orderFront(nil)
        }
    }

    func suspendInteraction() {
        ignoresMouseEvents = true
        resignKey()
    }

    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }
}
