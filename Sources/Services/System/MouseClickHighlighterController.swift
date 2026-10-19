import AppKit
import CoreGraphics
import QuartzCore

@MainActor
final class MouseClickHighlighterController {
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
            remove: { monitor in NSEvent.removeMonitor(monitor) }
        )
    }

    static let windowTitle = "Meow Mouse Click Highlighter"
    var onClick: ((NSPoint) -> Void)?

    private let eventMonitorDriver: EventMonitorDriver
    private let preparePanelForMonitoring: (@MainActor () -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var panel: NSPanel?
    private var ringLayer: CAShapeLayer?
    private var theme: AppTheme = .gingerCat
    private var generation: UInt64 = 0

    init(
        eventMonitorDriver: EventMonitorDriver = .appKit,
        preparePanelForMonitoring: (@MainActor () -> Void)? = nil
    ) {
        self.eventMonitorDriver = eventMonitorDriver
        self.preparePanelForMonitoring = preparePanelForMonitoring
    }

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    func apply(settings: AppSettings) {
        theme = settings.theme
        updateRingColor()
    }

    func prepareForRecording() {
        guard panel == nil else { return }
        let panelSize = CGSize(width: 96, height: 96)
        let ringSize = CGSize(width: 38, height: 38)
        let point = NSEvent.mouseLocation
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

        let ringLayer = CAShapeLayer()
        ringLayer.frame = CGRect(
            x: (panelSize.width - ringSize.width) / 2,
            y: (panelSize.height - ringSize.height) / 2,
            width: ringSize.width,
            height: ringSize.height
        )
        ringLayer.path = CGPath(ellipseIn: CGRect(origin: .zero, size: ringSize), transform: nil)
        ringLayer.lineWidth = 3
        ringLayer.opacity = 0
        view.layer?.addSublayer(ringLayer)
        panel.contentView = view

        self.panel = panel
        self.ringLayer = ringLayer
        updateRingColor()
        panel.orderFrontRegardless()
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        if let preparePanelForMonitoring {
            preparePanelForMonitoring()
        } else {
            prepareForRecording()
        }
        generation &+= 1
        let currentGeneration = generation
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = eventMonitorDriver.addGlobal(mask) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.show(at: NSEvent.mouseLocation)
            }
        }
        localMonitor = eventMonitorDriver.addLocal(mask) { [weak self] event in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.show(at: NSEvent.mouseLocation)
            }
            return event
        }
    }

    func pause() {
        generation &+= 1
        if let globalMonitor {
            eventMonitorDriver.remove(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            eventMonitorDriver.remove(localMonitor)
            self.localMonitor = nil
        }
        ringLayer?.removeAllAnimations()
        ringLayer?.opacity = 0
    }

    func stop() {
        pause()
        panel?.orderOut(nil)
        panel = nil
        ringLayer = nil
    }

    private func show(at point: NSPoint) {
        guard let panel, let ringLayer else { return }
        onClick?(point)
        panel.setFrameOrigin(NSPoint(
            x: point.x - panel.frame.width / 2,
            y: point.y - panel.frame.height / 2
        ))
        ringLayer.removeAllAnimations()
        animate(layer: ringLayer)
    }

    private func animate(layer: CAShapeLayer) {
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

        layer.add(scale, forKey: "click-scale")
        layer.add(opacity, forKey: "click-opacity")
        layer.opacity = 0
    }

    private func updateRingColor() {
        let color = Self.accentColor(for: theme)
        ringLayer?.fillColor = color.withAlphaComponent(0.14).cgColor
        ringLayer?.strokeColor = color.withAlphaComponent(0.95).cgColor
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
