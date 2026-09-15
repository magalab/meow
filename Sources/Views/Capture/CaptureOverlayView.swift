import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

final class CaptureOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CaptureOverlayController {
    private var panels: [CaptureOverlayPanel] = []
    private var continuation: CheckedContinuation<CaptureSelection?, Never>?
    private var isFinishing = false

    func present(session: CaptureSession, mode: ScreenshotCaptureMode) async -> CaptureSelection? {
        cancel()
        isFinishing = false

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.panels = session.displays.map { frozen in
                makePanel(frozen: frozen, windows: session.windows, mode: mode)
            }

            for panel in panels {
                panel.orderFrontRegardless()
            }
            panels.first?.makeKey()
            NSCursor.crosshair.push()
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func makePanel(
        frozen: FrozenDisplay,
        windows: [SCWindow],
        mode: ScreenshotCaptureMode
    ) -> CaptureOverlayPanel {
        let panel = CaptureOverlayPanel(
            contentRect: frozen.screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: frozen.screen
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        let candidates = windows.compactMap { window -> CaptureWindowCandidate? in
            let globalRect = ScreenCaptureService.appKitRect(fromCoreGraphics: window.frame)
            guard globalRect.intersects(frozen.screen.frame) else { return nil }
            let localRect = globalRect.offsetBy(
                dx: -frozen.screen.frame.minX,
                dy: -frozen.screen.frame.minY
            )
            return CaptureWindowCandidate(window: window, rect: localRect)
        }

        let view = CaptureOverlayView(
            frame: NSRect(origin: .zero, size: frozen.screen.frame.size),
            frozen: frozen,
            candidates: candidates,
            mode: mode,
            onSelect: { [weak self] selection in
                self?.finish(with: selection)
            },
            onCancel: { [weak self] in
                self?.finish(with: nil)
            }
        )
        panel.contentView = view
        return panel
    }

    private func finish(with selection: CaptureSelection?) {
        guard !isFinishing else { return }
        guard continuation != nil || !panels.isEmpty else { return }
        isFinishing = true

        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        NSCursor.pop()

        let pending = continuation
        continuation = nil
        pending?.resume(returning: selection)
    }
}

private struct CaptureWindowCandidate {
    let window: SCWindow
    let rect: CGRect
}

private final class CaptureOverlayView: NSView {
    private let frozen: FrozenDisplay
    private let candidates: [CaptureWindowCandidate]
    private let mode: ScreenshotCaptureMode
    private let onSelect: (CaptureSelection) -> Void
    private let onCancel: () -> Void

    private var dragStart: CGPoint?
    private var selectionRect: CGRect?
    private var hoveredWindow: CaptureWindowCandidate?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    init(
        frame: CGRect,
        frozen: FrozenDisplay,
        candidates: [CaptureWindowCandidate],
        mode: ScreenshotCaptureMode,
        onSelect: @escaping (CaptureSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.frozen = frozen
        self.candidates = candidates
        self.mode = mode
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let image = NSImage(
            cgImage: frozen.image,
            size: NSSize(width: frozen.display.width, height: frozen.display.height)
        )
        image.draw(in: bounds)

        let focusRect: CGRect?
        switch mode {
        case .region:
            focusRect = selectionRect
        case .window:
            focusRect = hoveredWindow?.rect
        case .display:
            focusRect = bounds.insetBy(dx: 4, dy: 4)
        }

        drawDimmedArea(excluding: focusRect)
        if let focusRect {
            drawFocusBorder(focusRect)
            if mode == .region {
                drawSizeLabel(for: focusRect)
            }
        } else {
            drawInstruction()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        updateHoveredWindow(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .region:
            dragStart = point
            selectionRect = CGRect(origin: point, size: .zero)
            needsDisplay = true
        case .window:
            updateHoveredWindow(at: point)
            if let hoveredWindow {
                onSelect(.window(hoveredWindow.window, scale: frozen.scale))
            }
        case .display:
            onSelect(.display(frozen.display, scale: frozen.scale))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectionRect = normalizedRect(from: dragStart, to: point).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region, let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = normalizedRect(from: dragStart, to: point).intersection(bounds).integral
        self.dragStart = nil
        guard rect.width >= 2, rect.height >= 2 else {
            selectionRect = nil
            needsDisplay = true
            return
        }
        onSelect(
            .region(
                display: frozen.display,
                rectInDisplayPoints: rect,
                scale: frozen.scale
            )
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func updateHoveredWindow(at point: CGPoint) {
        let candidate = candidates.first { $0.rect.contains(point) }
        guard candidate?.window.windowID != hoveredWindow?.window.windowID else { return }
        hoveredWindow = candidate
        needsDisplay = true
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func drawDimmedArea(excluding focusRect: CGRect?) {
        NSColor.black.withAlphaComponent(0.38).setFill()
        guard let rect = focusRect?.intersection(bounds), !rect.isEmpty else {
            bounds.fill()
            return
        }

        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: rect.minY - bounds.minY).fill()
        CGRect(x: bounds.minX, y: rect.maxY, width: bounds.width, height: bounds.maxY - rect.maxY).fill()
        CGRect(x: bounds.minX, y: rect.minY, width: rect.minX - bounds.minX, height: rect.height).fill()
        CGRect(x: rect.maxX, y: rect.minY, width: bounds.maxX - rect.maxX, height: rect.height).fill()
    }

    private func drawFocusBorder(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        NSColor.systemYellow.setStroke()
        path.stroke()
    }

    private func drawInstruction() {
        let text: String
        switch mode {
        case .region: text = L10n.screenshotOverlayRegionHint
        case .window: text = L10n.screenshotOverlayWindowHint
        case .display: text = L10n.screenshotOverlayDisplayHint
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let background = CGRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.midY - size.height / 2 - 9,
            width: size.width + 28,
            height: size.height + 18
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 10, yRadius: 10).fill()
        (text as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        let text = "\(Int(rect.width * frozen.scale)) × \(Int(rect.height * frozen.scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let x = min(max(rect.minX, 8), bounds.maxX - size.width - 24)
        let preferredY = rect.minY - size.height - 18
        let y = preferredY >= 8 ? preferredY : min(rect.maxY + 8, bounds.maxY - size.height - 16)
        let background = CGRect(x: x, y: y, width: size.width + 16, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(
            at: CGPoint(x: x + 8, y: y + 4),
            withAttributes: attributes
        )
    }
}
