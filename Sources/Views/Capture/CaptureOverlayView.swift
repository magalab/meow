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
    private var appResignObserver: NSObjectProtocol?

    func present(session: CaptureSession, mode: ScreenshotCaptureMode) async -> CaptureSelection? {
        cancel()
        isFinishing = false

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            appResignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            }
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
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
        }

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

enum CapturePixelMagnifierGeometry {
    static func sampleRect(
        at point: CGPoint,
        in bounds: CGRect,
        imageWidth: Int,
        imageHeight: Int,
        scale: CGFloat
    ) -> CGRect {
        let pixelX = min(max(0, Int((point.x * scale).rounded(.down))), imageWidth - 1)
        let pixelY = min(max(0, Int(((bounds.height - point.y) * scale).rounded(.down))), imageHeight - 1)
        let width = min(13, imageWidth)
        let height = min(13, imageHeight)
        return CGRect(
            x: min(max(0, pixelX - width / 2), imageWidth - width),
            y: min(max(0, pixelY - height / 2), imageHeight - height),
            width: width,
            height: height
        )
    }

    static func frame(near point: CGPoint, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: 140, height: 140)
        let margin: CGFloat = 22
        let x = point.x + margin + size.width <= bounds.maxX
            ? point.x + margin : point.x - margin - size.width
        let y = point.y - margin - size.height >= bounds.minY
            ? point.y - margin - size.height : point.y + margin
        return CGRect(
            x: min(max(bounds.minX, x), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(bounds.minY, y), max(bounds.minY, bounds.maxY - size.height)),
            width: size.width,
            height: size.height
        )
    }
}

private final class CaptureOverlayView: NSView {
    private let frozen: FrozenDisplay
    private let candidates: [CaptureWindowCandidate]
    private let mode: ScreenshotCaptureMode
    private let onSelect: (CaptureSelection) -> Void
    private let onCancel: () -> Void

    private var dragStart: CGPoint?
    private var selectionRect: CGRect?
    private var selectionPointer: CGPoint?
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
        MeowLog.capture.error("Capture overlay view cannot be decoded from a storyboard")
        return nil
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
            } else if mode == .window, let hoveredWindow {
                drawWindowLabel(for: hoveredWindow)
            }
        } else {
            drawInstruction()
        }
        if mode == .region, dragStart != nil, let selectionPointer {
            drawPixelMagnifier(at: selectionPointer)
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
            selectionPointer = point
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
        selectionPointer = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard mode == .region, let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = normalizedRect(from: dragStart, to: point).intersection(bounds).integral
        self.dragStart = nil
        selectionPointer = nil
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

    private func drawWindowLabel(for candidate: CaptureWindowCandidate) {
        let applicationName = candidate.window.owningApplication?.applicationName ?? ""
        let title = candidate.window.title ?? ""
        let dimensions = "\(Int(candidate.window.frame.width * frozen.scale)) × \(Int(candidate.window.frame.height * frozen.scale))"
        let label = ([applicationName, title].filter { !$0.isEmpty } + [dimensions])
            .joined(separator: " · ") as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        let width = min(bounds.width - 16, label.size(withAttributes: attributes).width + 16)
        let height: CGFloat = 24
        let x = min(max(8, candidate.rect.minX), bounds.maxX - width - 8)
        let above = candidate.rect.maxY + 8
        let y = above + height <= bounds.maxY ? above : max(8, candidate.rect.minY - height - 8)
        let background = CGRect(x: x, y: y, width: width, height: height)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        label.draw(in: background.insetBy(dx: 8, dy: 4), withAttributes: attributes)
    }

    private func drawPixelMagnifier(at point: CGPoint) {
        let image = frozen.image
        let scale = frozen.scale
        let pixelX = min(max(0, Int((point.x * scale).rounded(.down))), image.width - 1)
        let pixelY = min(max(0, Int(((bounds.height - point.y) * scale).rounded(.down))), image.height - 1)
        let pixelRect = CapturePixelMagnifierGeometry.sampleRect(
            at: point,
            in: bounds,
            imageWidth: image.width,
            imageHeight: image.height,
            scale: scale
        )
        guard let cropped = image.cropping(to: pixelRect) else { return }

        let lens = CapturePixelMagnifierGeometry.frame(near: point, in: bounds)
        let imageRect = lens.insetBy(dx: 5, dy: 5)
        NSColor.black.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: lens, xRadius: 8, yRadius: 8).fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: cropped, size: imageRect.size).draw(in: imageRect)
        NSGraphicsContext.restoreGraphicsState()

        let cellWidth = imageRect.width / pixelRect.width
        let cellHeight = imageRect.height / pixelRect.height
        let grid = NSBezierPath()
        for index in 1..<Int(pixelRect.width) {
            let x = imageRect.minX + CGFloat(index) * cellWidth
            grid.move(to: CGPoint(x: x, y: imageRect.minY))
            grid.line(to: CGPoint(x: x, y: imageRect.maxY))
        }
        for index in 1..<Int(pixelRect.height) {
            let y = imageRect.minY + CGFloat(index) * cellHeight
            grid.move(to: CGPoint(x: imageRect.minX, y: y))
            grid.line(to: CGPoint(x: imageRect.maxX, y: y))
        }
        grid.lineWidth = 0.5
        NSColor.black.withAlphaComponent(0.4).setStroke()
        grid.stroke()

        let markerX = imageRect.minX + (CGFloat(pixelX) - pixelRect.minX + 0.5) * cellWidth
        let markerY = imageRect.maxY - (CGFloat(pixelY) - pixelRect.minY + 0.5) * cellHeight
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: markerX - cellWidth, y: markerY))
        crosshair.line(to: CGPoint(x: markerX + cellWidth, y: markerY))
        crosshair.move(to: CGPoint(x: markerX, y: markerY - cellHeight))
        crosshair.line(to: CGPoint(x: markerX, y: markerY + cellHeight))
        crosshair.lineWidth = 2
        NSColor.systemYellow.setStroke()
        crosshair.stroke()

        NSBezierPath(roundedRect: lens, xRadius: 8, yRadius: 8).stroke()
    }

}
