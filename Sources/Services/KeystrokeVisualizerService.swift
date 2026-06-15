import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

final class KeystrokeOverlayPanel: NSPanel {
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?

    private var dragStartMouseLocation: NSPoint?
    private var dragStartOrigin: NSPoint?

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartOrigin = frame.origin
        onDragBegan?()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartMouseLocation, let dragStartOrigin else {
            super.mouseDragged(with: event)
            return
        }

        let current = NSEvent.mouseLocation
        let deltaX = current.x - dragStartMouseLocation.x
        let deltaY = current.y - dragStartMouseLocation.y
        setFrameOrigin(NSPoint(x: dragStartOrigin.x + deltaX, y: dragStartOrigin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartMouseLocation = nil
        dragStartOrigin = nil
        onDragEnded?(NSPoint(x: frame.midX, y: frame.midY))
        super.mouseUp(with: event)
    }
}

@MainActor
final class KeystrokeVisualizerService: ObservableObject {
    var onOverlayPlacementChanged: ((KeystrokeOverlayPosition, KeystrokeOverlayPoint?) -> Void)?
    @Published private(set) var permissionState: KeystrokePermissionState = .unknown

    private let viewModel = KeystrokeOverlayViewModel()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayWindow: KeystrokeOverlayPanel?
    private var hostingController: NSHostingController<KeystrokeOverlayView>?
    private var hideWorkItem: DispatchWorkItem?
    private var pendingModifierWorkItem: DispatchWorkItem?

    private var isEnabled = false
    private var showModifierOnly = true
    private var overlayPosition: KeystrokeOverlayPosition = .bottomCenter
    private var overlayPoint: KeystrokeOverlayPoint?
    private var style: KeystrokeOverlayStyle = .compact
    private var displayDuration: KeystrokeDisplayDuration = .normal
    private var customDisplayDuration: Double = 1.4
    private var overlayOpacity: Double = 0.82
    private var historyCount: KeystrokeHistoryCount = .one
    private var displayMode: KeystrokeDisplayMode = .shortcutsAndSpecialKeys
    private var theme: AppTheme = .gingerCat

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func apply(settings: AppSettings) {
        showModifierOnly = settings.keystrokeVisualizerShowModifierOnly
        overlayPosition = settings.keystrokeVisualizerOverlayPosition
        overlayPoint = settings.keystrokeVisualizerOverlayPoint
        style = settings.keystrokeVisualizerStyle
        displayDuration = settings.keystrokeVisualizerDisplayDuration
        customDisplayDuration = settings.keystrokeVisualizerCustomDisplayDuration
        overlayOpacity = settings.keystrokeVisualizerOpacity
        historyCount = settings.keystrokeVisualizerHistoryCount
        displayMode = settings.keystrokeVisualizerDisplayMode
        theme = settings.theme
        viewModel.apply(theme: theme, style: style, opacity: overlayOpacity, historyCount: historyCount)
        updateOverlaySizeAndPosition(force: true)

        if settings.keystrokeVisualizerEnabled {
            start()
        } else {
            stop()
            refreshPermissionState(prompt: false)
        }
    }

    func refreshPermissionState(prompt: Bool = false) {
        if requestPermission(prompt: prompt) {
            if permissionState != .unavailable {
                permissionState = .trusted
            }
        } else {
            permissionState = .denied
        }
    }

    func retryAfterPermissionChange() {
        guard isEnabled else {
            refreshPermissionState(prompt: false)
            return
        }

        if eventTap == nil {
            start()
        } else {
            refreshPermissionState(prompt: false)
        }
    }

    func stop() {
        isEnabled = false
        hideWorkItem?.cancel()
        hideWorkItem = nil
        pendingModifierWorkItem?.cancel()
        pendingModifierWorkItem = nil
        viewModel.clear()
        overlayWindow?.orderOut(nil)

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }

    private func start() {
        isEnabled = true
        guard eventTap == nil else { return }

        guard requestPermission(prompt: true) else {
            permissionState = .denied
            return
        }

        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue) |
            CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keystrokeEventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            permissionState = .unavailable
            NSLog("[Meow] Failed to create keystroke visualizer event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        permissionState = .trusted
    }

    private func requestPermission(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        )
    }

    fileprivate func handleEvent(type: CGEventType, keyCode: UInt32, flags: CGEventFlags) {
        guard isEnabled else { return }
        guard !InternalInputEventSuppressor.isSuppressed else {
            cancelPendingModifierDisplay()
            return
        }

        switch type {
        case .keyDown:
            cancelPendingModifierDisplay()
            guard !KeyDisplayFormatter.isModifierOnlyKey(keyCode) else { return }
            guard KeyDisplayFormatter.shouldDisplay(keyCode: keyCode, flags: flags, mode: displayMode) else { return }
            show(label: KeyDisplayFormatter.keystrokeLabel(keyCode: keyCode, flags: flags), isModifierOnly: false)
        case .flagsChanged:
            guard showModifierOnly,
                  isModifierPressed(keyCode: keyCode, flags: flags),
                  let label = KeyDisplayFormatter.modifierLabel(flags: flags)
            else {
                cancelPendingModifierDisplay()
                return
            }
            scheduleModifierDisplay(label: label)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        default:
            break
        }
    }

    private func show(label: String, isModifierOnly: Bool) {
        ensureOverlayWindow()
        viewModel.show(label: label, isModifierOnly: isModifierOnly)

        guard let overlayWindow else { return }
        updateOverlaySizeAndPosition(force: !overlayWindow.isVisible)
        overlayWindow.alphaValue = 1
        overlayWindow.orderFrontRegardless()
        scheduleHide()
    }

    private func scheduleModifierDisplay(label: String) {
        pendingModifierWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.pendingModifierWorkItem = nil
                self?.show(label: label, isModifierOnly: true)
            }
        }
        pendingModifierWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }

    private func cancelPendingModifierDisplay() {
        pendingModifierWorkItem?.cancel()
        pendingModifierWorkItem = nil
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.hideOverlay()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + displayDuration.seconds(customSeconds: customDisplayDuration),
            execute: workItem
        )
    }

    private func hideOverlay() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let overlayWindow, overlayWindow.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            overlayWindow.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.viewModel.clear()
                self?.overlayWindow?.orderOut(nil)
                self?.overlayWindow?.alphaValue = 1
            }
        }
    }

    private func ensureOverlayWindow() {
        guard overlayWindow == nil else { return }

        let window = KeystrokeOverlayPanel(
            contentRect: NSRect(origin: .zero, size: overlaySize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.onDragBegan = { [weak self] in
            self?.hideWorkItem?.cancel()
            self?.hideWorkItem = nil
        }
        window.onDragEnded = { [weak self] center in
            guard let self else { return }
            self.overlayPosition = .custom
            self.overlayPoint = self.normalizedPoint(for: center)
            self.onOverlayPlacementChanged?(.custom, self.overlayPoint)
            self.scheduleHide()
        }

        let hosting = NSHostingController(rootView: KeystrokeOverlayView(viewModel: viewModel))
        hosting.view.frame = NSRect(origin: .zero, size: overlaySize)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = hosting

        overlayWindow = window
        hostingController = hosting
        updateOverlaySizeAndPosition(force: true)
    }

    private func updateOverlaySizeAndPosition(force: Bool) {
        guard let overlayWindow else { return }
        let size = overlaySize
        overlayWindow.setContentSize(size)
        hostingController?.view.frame = NSRect(origin: .zero, size: size)

        guard force || !overlayWindow.isVisible else { return }
        overlayWindow.setFrameOrigin(origin(for: size))
    }

    private var overlaySize: NSSize {
        KeystrokeOverlayLayout.size(style: style, historyCount: historyCount)
    }

    private func origin(for size: NSSize) -> NSPoint {
        let visibleFrame = activeScreen().visibleFrame
        let center: NSPoint

        if overlayPosition == .custom, let overlayPoint {
            let x = visibleFrame.minX + visibleFrame.width * CGFloat(clamped(overlayPoint.x))
            let y = visibleFrame.minY + visibleFrame.height * CGFloat(clamped(overlayPoint.y))
            center = NSPoint(x: x, y: y)
        } else {
            center = presetCenter(for: overlayPosition, in: visibleFrame, size: size)
        }

        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return clampedOrigin(origin, size: size, visibleFrame: visibleFrame)
    }

    private func normalizedPoint(for center: NSPoint) -> KeystrokeOverlayPoint {
        let visibleFrame = screen(containing: center).visibleFrame
        let x = Double((center.x - visibleFrame.minX) / visibleFrame.width)
        let y = Double((center.y - visibleFrame.minY) / visibleFrame.height)
        return KeystrokeOverlayPoint(x: clamped(x), y: clamped(y))
    }

    private func presetCenter(for position: KeystrokeOverlayPosition, in visibleFrame: NSRect, size: NSSize) -> NSPoint {
        let margin: CGFloat = 72
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let left = visibleFrame.minX + halfWidth + margin
        let right = visibleFrame.maxX - halfWidth - margin
        let top = visibleFrame.maxY - halfHeight - margin
        let bottom = visibleFrame.minY + halfHeight + margin

        switch position {
        case .topCenter:
            return NSPoint(x: visibleFrame.midX, y: top)
        case .bottomLeft:
            return NSPoint(x: left, y: bottom)
        case .bottomRight:
            return NSPoint(x: right, y: bottom)
        case .topLeft:
            return NSPoint(x: left, y: top)
        case .topRight:
            return NSPoint(x: right, y: top)
        case .bottomCenter, .custom:
            return NSPoint(x: visibleFrame.midX, y: bottom)
        }
    }

    private func activeScreen() -> NSScreen {
        screen(containing: NSEvent.mouseLocation)
    }

    private func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.visibleFrame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }

    private func isModifierPressed(keyCode: UInt32, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55:
            return flags.contains(.maskCommand)
        case 56, 60:
            return flags.contains(.maskShift)
        case 58, 61:
            return flags.contains(.maskAlternate)
        case 59, 62:
            return flags.contains(.maskControl)
        case 57:
            return flags.contains(.maskAlphaShift)
        case 63:
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }
}

private let keystrokeEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<KeystrokeVisualizerService>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    DispatchQueue.main.async { @MainActor in
        service.handleEvent(type: type, keyCode: keyCode, flags: flags)
    }

    return Unmanaged.passUnretained(event)
}
