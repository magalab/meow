import AppKit

@MainActor
final class RecordingRegionBorderController {
    static let windowTitle = "Meow Recording Region Border"

    private var panel: NSPanel?

    static func globalFrame(for rectInDisplayPoints: CGRect, screenFrame: CGRect) -> CGRect {
        rectInDisplayPoints.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
    }

    func show(_ rectInDisplayPoints: CGRect, on screen: NSScreen) {
        stop()
        let frame = Self.globalFrame(
            for: rectInDisplayPoints,
            screenFrame: screen.frame
        )
        guard frame.width > 0, frame.height > 0 else { return }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.windowTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.contentView = RecordingRegionBorderView(frame: CGRect(origin: .zero, size: frame.size))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func stop() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class RecordingRegionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 2
        path.setLineDash([7, 5], count: 2, phase: 0)
        NSColor.systemYellow.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }
}
