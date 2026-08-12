import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScrollingCaptureAutoScrollResult {
    case started
    case stopped
    case permissionRequired
}

@MainActor
final class ScrollingCaptureController {
    var onProgress: ((ScrollingCaptureProgress) -> Void)?
    var onPreview: ((CGImage) -> Void)?
    var onIssue: ((String) -> Void)?
    var onAccessibilityPermissionRequired: (() -> Void)?

    private let captureService: ScreenCaptureService
    private let display: SCDisplay
    private let screen: NSScreen
    private let rectInDisplayPoints: CGRect
    private let scale: CGFloat
    private let settings: ScrollingCaptureSettings

    private var processor: ScrollingCaptureProcessor?
    private var continuation: CheckedContinuation<ScrollingCaptureSessionResult, Never>?
    private var globalScrollMonitor: Any?
    private var localScrollMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var settlementTask: Task<Void, Never>?
    private var autoScrollTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var isActive = false
    private var isPaused = false
    private var isCapturingFrame = false
    private var needsSettledCapture = false
    private var isAutoScrolling = false
    private var lastCaptureTime: TimeInterval = 0
    private var lastPreviewTime: TimeInterval = 0
    private var targetApplicationPID: pid_t?

    init(
        captureService: ScreenCaptureService,
        display: SCDisplay,
        screen: NSScreen,
        rectInDisplayPoints: CGRect,
        scale: CGFloat,
        settings: ScrollingCaptureSettings
    ) {
        self.captureService = captureService
        self.display = display
        self.screen = screen
        self.rectInDisplayPoints = rectInDisplayPoints
        self.scale = scale
        self.settings = settings
    }

    func run() async -> ScrollingCaptureSessionResult {
        cancel()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            onProgress?(progressWithoutProcessor(state: .preparing))
            startupTask = Task { @MainActor [weak self] in
                await self?.startSession()
            }
        }
    }

    func togglePause() {
        guard isActive else { return }
        if isPaused {
            isPaused = false
            Task { await processor?.resumeAfterPause() }
            installManualMonitorsIfNeeded()
            emitProgress(state: .capturing)
        } else {
            isPaused = true
            stopAutoScroll()
            settlementTask?.cancel()
            removeScrollMonitors()
            emitProgress(state: .paused)
        }
    }

    func toggleAutoScroll() -> ScrollingCaptureAutoScrollResult {
        guard isActive else { return .stopped }
        if isAutoScrolling {
            stopAutoScroll()
            installManualMonitorsIfNeeded()
            emitProgress(state: isPaused ? .paused : .capturing)
            return .stopped
        }
        guard AXIsProcessTrusted() else { return .permissionRequired }
        isPaused = false
        removeScrollMonitors()
        startAutoScroll()
        return .started
    }

    func finish() {
        guard isActive else { return }
        Task { @MainActor [weak self] in
            await self?.finishSession()
        }
    }

    func cancel() {
        guard continuation != nil || isActive else { return }
        isActive = false
        isPaused = false
        stopTasksAndMonitors()
        processor = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: .cancelled)
    }

    private func startSession() async {
        defer { startupTask = nil }
        do {
            try await Task.sleep(for: .milliseconds(120))
            guard continuation != nil else { return }
            let firstFrame = try await captureSettledFrame()
            try Task.checkCancellation()
            guard continuation != nil else { return }
            let processor = ScrollingCaptureProcessor(firstFrame: firstFrame, settings: settings)
            self.processor = processor
            targetApplicationPID = resolveTargetApplicationPID()
            activateTargetApplication()
            isActive = true
            isPaused = false
            isAutoScrolling = false
            installKeyMonitors()

            let initial = await processor.initialProgress(isAutoScrolling: false)
            onProgress?(initial)
            if let preview = await processor.makePreview() {
                onPreview?(preview)
            }

            if settings.autoScrollEnabled {
                if AXIsProcessTrusted() {
                    startAutoScroll()
                } else {
                    installManualMonitorsIfNeeded()
                    onAccessibilityPermissionRequired?()
                }
            } else {
                installManualMonitorsIfNeeded()
            }
        } catch {
            if error is CancellationError {
                cancel()
                return
            }
            NSLog("[Meow] Scrolling capture could not start: %@", error.localizedDescription)
            onIssue?(error.localizedDescription)
            isActive = false
            stopTasksAndMonitors()
            let pending = continuation
            continuation = nil
            pending?.resume(returning: .failed(error))
        }
    }

    private func captureSettledFrame() async throws -> CGImage {
        try Task.checkCancellation()
        var previous = try await captureService.captureLiveRegion(
            display: display,
            rectInDisplayPoints: rectInDisplayPoints,
            scale: scale
        )
        for attempt in 0..<6 {
            let delay = 35 + attempt * 15
            try await Task.sleep(for: .milliseconds(delay))
            let current = try await captureService.captureLiveRegion(
                display: display,
                rectInDisplayPoints: rectInDisplayPoints,
                scale: scale
            )
            let stable = await Task.detached(priority: .userInitiated) { @Sendable [previous, current] in
                ScrollingCaptureMatcher.framesAreStable(previous, current)
            }.value
            try Task.checkCancellation()
            if stable {
                return current
            }
            previous = current
        }
        return previous
    }

    private func captureAndProcess(settled: Bool) async {
        guard isActive, !isPaused, let processor else { return }
        if isCapturingFrame {
            if settled {
                needsSettledCapture = true
            }
            return
        }
        isCapturingFrame = true
        defer {
            isCapturingFrame = false
            if needsSettledCapture, isActive, !isPaused {
                needsSettledCapture = false
                Task { @MainActor [weak self] in
                    await self?.captureAndProcess(settled: true)
                }
            }
        }

        do {
            let frame: CGImage
            if settled {
                frame = try await captureSettledFrame()
            } else {
                frame = try await captureService.captureLiveRegion(
                    display: display,
                    rectInDisplayPoints: rectInDisplayPoints,
                    scale: scale
                )
            }
            guard isActive, !isPaused else { return }
            let outcome = await processor.process(frame, isAutoScrolling: isAutoScrolling)
            switch outcome {
            case let .appended(progress):
                onProgress?(progress)
                await emitPreviewIfNeeded(force: false)
            case let .waiting(progress):
                onProgress?(progress)
            case let .paused(progress):
                isPaused = true
                stopAutoScroll()
                removeScrollMonitors()
                onProgress?(progress)
                onIssue?(L10n.scrollingCaptureErrorNoOverlap)
            case let .reachedLimit(reason, progress):
                onProgress?(progress)
                switch reason {
                case .maximumHeight:
                    onIssue?(L10n.scrollingCaptureReachedMaximumHeight)
                case .maximumPixels:
                    onIssue?(L10n.scrollingCaptureReachedMaximumPixels)
                case .completed, .consecutiveMatchFailures:
                    break
                }
                await finishSession()
            }
        } catch is CancellationError {
            return
        } catch {
            NSLog("[Meow] Scrolling capture frame failed: %@", error.localizedDescription)
            isPaused = true
            stopAutoScroll()
            removeScrollMonitors()
            emitProgress(state: .failed(error.localizedDescription))
            onIssue?(error.localizedDescription)
        }
    }

    private func finishSession() async {
        guard isActive, let processor else { return }
        isActive = false
        stopTasksAndMonitors()
        let progress = await processor.progress(state: .finishing, isAutoScrolling: false)
        onProgress?(progress)
        let finalImage = await processor.makeFinalImage()
        self.processor = nil
        let pending = continuation
        continuation = nil
        if let finalImage {
            pending?.resume(returning: .completed(finalImage))
        } else {
            pending?.resume(returning: .failed(ScrollingCaptureError.finalCompositionFailed))
        }
    }

    private func onManualScroll(at mouseLocation: CGPoint) {
        guard isActive, !isPaused, !isAutoScrolling else { return }
        guard Self.shouldHandleManualScroll(
            at: mouseLocation,
            captureRectInDisplayPoints: rectInDisplayPoints,
            screenFrame: screen.frame
        ) else { return }
        settlementTask?.cancel()
        let settlementDelay = settings.settlementDelay
        settlementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(settlementDelay))
            guard !Task.isCancelled else { return }
            await self?.captureAndProcess(settled: true)
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCaptureTime >= settings.manualCaptureInterval else { return }
        lastCaptureTime = now
        Task { @MainActor [weak self] in
            await self?.captureAndProcess(settled: false)
        }
    }

    private func startAutoScroll() {
        guard isActive, !isAutoScrolling else { return }
        isAutoScrolling = true
        isPaused = false
        activateTargetApplication()
        warpPointerIntoCaptureRegion()
        emitProgress(state: .capturing)

        autoScrollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            while !Task.isCancelled, isActive, isAutoScrolling, !isPaused {
                activateTargetApplication()
                if let event = CGEvent(
                    scrollWheelEvent2Source: nil,
                    units: .line,
                    wheelCount: 1,
                    wheel1: -settings.autoScrollSpeed.scrollLines,
                    wheel2: 0,
                    wheel3: 0
                ) {
                    event.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(for: .milliseconds(90))
                await captureAndProcess(settled: true)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func stopAutoScroll() {
        isAutoScrolling = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func installManualMonitorsIfNeeded() {
        guard isActive, !isPaused, !isAutoScrolling, globalScrollMonitor == nil else { return }
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor in
                self?.onManualScroll(at: mouseLocation)
            }
        }
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor in
                self?.onManualScroll(at: mouseLocation)
            }
            return event
        }
    }

    private func removeScrollMonitors() {
        if let globalScrollMonitor {
            NSEvent.removeMonitor(globalScrollMonitor)
            self.globalScrollMonitor = nil
        }
        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
            self.localScrollMonitor = nil
        }
    }

    private func installKeyMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.finish() }
                return nil
            }
            return event
        }
        if AXIsProcessTrusted() {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                Task { @MainActor in self?.finish() }
            }
        }
    }

    private func stopTasksAndMonitors() {
        needsSettledCapture = false
        startupTask?.cancel()
        startupTask = nil
        settlementTask?.cancel()
        settlementTask = nil
        stopAutoScroll()
        removeScrollMonitors()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func emitProgress(state: ScrollingCaptureState) {
        guard let processor else {
            onProgress?(progressWithoutProcessor(state: state))
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let progress = await processor.progress(
                state: state,
                isAutoScrolling: isAutoScrolling
            )
            onProgress?(progress)
        }
    }

    private func emitPreviewIfNeeded(force: Bool) async {
        guard let processor else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastPreviewTime >= 0.25 else { return }
        lastPreviewTime = now
        if let preview = await processor.makePreview() {
            onPreview?(preview)
        }
    }

    private func progressWithoutProcessor(state: ScrollingCaptureState) -> ScrollingCaptureProgress {
        var progress = ScrollingCaptureProgress.idle
        progress.state = state
        progress.isAutoScrolling = isAutoScrolling
        return progress
    }

    private func resolveTargetApplicationPID() -> pid_t? {
        let center = CGPoint(x: captureRectInScreenPoints.midX, y: captureRectInScreenPoints.midY)
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in windowInfo {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let coreGraphicsRect = CGRect(
                      dictionaryRepresentation: bounds as CFDictionary
                  ),
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber
            else { continue }
            let pid = pid_t(pidNumber.int32Value)
            let appKitRect = ScreenCaptureService.appKitRect(fromCoreGraphics: coreGraphicsRect)
            if appKitRect.contains(center),
               NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != Bundle.main.bundleIdentifier
            {
                return pid
            }
        }
        return nil
    }

    private func activateTargetApplication() {
        guard let targetApplicationPID else { return }
        NSRunningApplication(processIdentifier: targetApplicationPID)?.activate(options: [])
    }

    private func warpPointerIntoCaptureRegion() {
        let appKitPoint = CGPoint(
            x: screen.frame.minX + rectInDisplayPoints.midX,
            y: screen.frame.minY + rectInDisplayPoints.midY
        )
        let primaryTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: appKitPoint.x, y: primaryTop - appKitPoint.y))
    }

    private var captureRectInScreenPoints: CGRect {
        rectInDisplayPoints.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    nonisolated static func shouldHandleManualScroll(
        at mouseLocation: CGPoint,
        captureRectInDisplayPoints: CGRect,
        screenFrame: CGRect
    ) -> Bool {
        captureRectInDisplayPoints
            .offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
            .contains(mouseLocation)
    }
}
