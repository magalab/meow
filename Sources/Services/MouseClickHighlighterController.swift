import AppKit
import QuartzCore

@MainActor
final class MouseClickHighlighterController {
    static let windowTitle = "Meow Mouse Click Highlighter"

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var panels: [NSPanel] = []
    private var theme: AppTheme = .gingerCat

    func apply(settings: AppSettings) {
        theme = settings.theme
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.show(at: NSEvent.mouseLocation) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.show(at: NSEvent.mouseLocation) }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func show(at point: NSPoint) {
        let panelSize = CGSize(width: 96, height: 96)
        let ringSize = CGSize(width: 38, height: 38)
        let panel = NSPanel(
            contentRect: NSRect(
                x: point.x - panelSize.width / 2,
                y: point.y - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.windowTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(origin: .zero, size: panelSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.masksToBounds = false

        let ringFrame = CGRect(
            x: (panelSize.width - ringSize.width) / 2,
            y: (panelSize.height - ringSize.height) / 2,
            width: ringSize.width,
            height: ringSize.height
        )
        let ringLayer = CAShapeLayer()
        let color = Self.accentColor(for: theme)
        ringLayer.frame = ringFrame
        ringLayer.path = CGPath(ellipseIn: CGRect(origin: .zero, size: ringSize), transform: nil)
        ringLayer.fillColor = color.withAlphaComponent(0.14).cgColor
        ringLayer.strokeColor = color.withAlphaComponent(0.95).cgColor
        ringLayer.lineWidth = 3
        view.layer?.addSublayer(ringLayer)
        panel.contentView = view

        panels.append(panel)
        panel.orderFrontRegardless()
        animate(panel: panel, layer: ringLayer)
    }

    private func animate(panel: NSPanel, layer: CALayer?) {
        let duration: CFTimeInterval = 0.42
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.7
        scale.toValue = 1.65
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.95
        opacity.toValue = 0
        opacity.duration = duration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)

        layer?.add(scale, forKey: "click-scale")
        layer?.add(opacity, forKey: "click-opacity")
        layer?.opacity = 0

        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
            guard let panel else { return }
            panel.orderOut(nil)
            self?.panels.removeAll { $0 === panel }
        }
    }

    private static func accentColor(for theme: AppTheme) -> NSColor {
        switch theme {
        case .gingerCat:
            return NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.24, alpha: 1)
        case .mistBlue:
            return NSColor(calibratedRed: 0.23, green: 0.31, blue: 0.54, alpha: 1)
        case .graphiteAmber:
            return NSColor(calibratedRed: 0.77, green: 0.54, blue: 0.23, alpha: 1)
        case .mossInk:
            return NSColor(calibratedRed: 0.29, green: 0.42, blue: 0.34, alpha: 1)
        }
    }
}
