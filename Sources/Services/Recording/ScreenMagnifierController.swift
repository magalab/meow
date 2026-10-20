import MeowRecording
import AppKit
import CoreImage
import CoreGraphics
import CoreMedia
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenMagnifierController: NSObject, SCStreamOutput, SCStreamDelegate {
    static let windowTitle = "Meow Screen Magnifier"

    var onError: ((Error) -> Void)?
    var onFrame: ((CGImage?, CGRect, CGPoint, Int, Bool) -> Void)?
    var onPosition: ((CGRect) -> Void)?

    private var settings = RecordingSettings.default
    private var panel: NSPanel?
    private var contentView: MagnifierContentView?
    private var timer: Timer?
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]
    private var ownApplication: SCRunningApplication?
    private var captureStream: SCStream?
    private var captureDisplayID: CGDirectDisplayID?
    private var isSwitchingDisplay = false
    private var isStarting = false
    private var generation: UInt64 = 0
    private let ciContext = CIContext()
    private var hasLoggedFrame = false

    var isVisible: Bool { panel?.isVisible == true }

    func apply(settings: RecordingSettings) {
        let updated = settings.normalized()
        let presentationChanged = updated.magnifierZoom != self.settings.magnifierZoom
            || updated.magnifierWindowWidth != self.settings.magnifierWindowWidth
            || updated.magnifierCircular != self.settings.magnifierCircular
        self.settings = updated
        guard presentationChanged else { return }
        contentView?.zoom = updated.magnifierZoom
        contentView?.circular = updated.magnifierCircular
        positionPanel(near: NSEvent.mouseLocation)
    }

    func toggle() async throws {
        if panel != nil || isStarting {
            stop()
        } else {
            try await start()
        }
    }

    func start() async throws {
        guard panel == nil, !isStarting else { return }
        generation &+= 1
        let currentGeneration = generation
        isStarting = true
        hasLoggedFrame = false
        let panelSize = CGSize(
            width: CGFloat(settings.magnifierWindowWidth),
            height: CGFloat(settings.magnifierWindowWidth) * (settings.magnifierCircular ? 1.0 : 2.0 / 3.0)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.windowTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.sharingType = .none

        let contentView = MagnifierContentView(
            frame: NSRect(origin: .zero, size: panelSize),
            zoom: settings.magnifierZoom,
            circular: settings.magnifierCircular
        )
        contentView.autoresizingMask = [.width, .height]
        panel.contentView = contentView

        self.panel = panel
        self.contentView = contentView
        positionPanel(near: NSEvent.mouseLocation)
        do {
            try await refreshShareableContent(generation: currentGeneration)
            guard generation == currentGeneration else { return }
            guard let displayID = Self.displayID(at: NSEvent.mouseLocation) else {
                throw RecordingError.magnifierUnavailable
            }
            try await startCapture(on: displayID, generation: currentGeneration)
            guard generation == currentGeneration else { return }
            panel.orderFrontRegardless()
            isStarting = false
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.followPointerAndSwitchDisplay(generation: currentGeneration)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } catch {
            guard generation == currentGeneration else { return }
            stop()
            throw error
        }
    }

    private func followPointerAndSwitchDisplay(generation currentGeneration: UInt64) {
        guard generation == currentGeneration else { return }
        let pointer = NSEvent.mouseLocation
        positionPanel(near: pointer)
        guard !isSwitchingDisplay,
              let displayID = Self.displayID(at: pointer),
              displayID != captureDisplayID
        else { return }
        isSwitchingDisplay = true
        Task { @MainActor in
            defer {
                if generation == currentGeneration { isSwitchingDisplay = false }
            }
            do {
                try await refreshShareableContent(generation: currentGeneration)
                guard generation == currentGeneration else { return }
                try await startCapture(on: displayID, generation: currentGeneration)
            } catch {
                guard generation == currentGeneration else { return }
                stop()
                onError?(error)
            }
        }
    }

    func stop() {
        generation &+= 1
        isStarting = false
        timer?.invalidate()
        timer = nil
        let captureStream = self.captureStream
        self.captureStream = nil
        captureDisplayID = nil
        isSwitchingDisplay = false
        if let captureStream {
            Task { try? await captureStream.stopCapture() }
        }
        panel?.orderOut(nil)
        panel = nil
        contentView = nil
        displays = [:]
        ownApplication = nil
        onFrame?(nil, .zero, .zero, settings.magnifierZoom, settings.magnifierCircular)
    }

    private func refreshShareableContent(generation currentGeneration: UInt64) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard generation == currentGeneration else { return }
        displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
        ownApplication = content.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
    }

    private func startCapture(on displayID: CGDirectDisplayID, generation currentGeneration: UInt64) async throws {
        guard generation == currentGeneration,
              let display = displays[displayID],
              let ownApplication
        else { throw RecordingError.magnifierUnavailable }
        let previousStream = captureStream
        captureStream = nil
        captureDisplayID = nil
        if let previousStream {
            try? await previousStream.stopCapture()
        }
        guard generation == currentGeneration else { return }
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = true
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [ownApplication],
            exceptingWindows: []
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        captureStream = stream
        captureDisplayID = displayID
        do {
            try await stream.startCapture()
        } catch {
            if captureStream === stream {
                captureStream = nil
                captureDisplayID = nil
            }
            throw error
        }
        if generation != currentGeneration {
            try? await stream.stopCapture()
        }
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }
        let buffer = MagnifierSampleBuffer(sampleBuffer)
        MainActor.assumeIsolated {
            render(buffer.value, from: stream)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard captureStream === stream else { return }
            stop()
            onError?(error)
        }
    }

    private func render(_ sampleBuffer: CMSampleBuffer, from stream: SCStream) {
        guard captureStream === stream,
              let panel,
              let displayID = captureDisplayID,
              let screen = NSScreen.screens.first(where: { Self.displayID(for: $0) == displayID }),
              let pixelBuffer = sampleBuffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete
        else { return }
        let pointer = NSEvent.mouseLocation
        let zoom = settings.magnifierZoom
        let circular = settings.magnifierCircular
        let captureSize = CGSize(
            width: panel.frame.width / CGFloat(zoom),
            height: panel.frame.height / CGFloat(zoom)
        )
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let cropRect = Self.streamCropRect(
            centeredAt: pointer,
            in: screen.frame,
            imageSize: image.extent.size,
            captureSize: captureSize
        )
        guard let snapshot = ciContext.createCGImage(image, from: cropRect) else { return }
        let localPointer = CGPoint(
            x: (pointer.x - screen.frame.minX) / screen.frame.width * image.extent.width,
            y: (pointer.y - screen.frame.minY) / screen.frame.height * image.extent.height
        )
        contentView?.image = NSImage(cgImage: snapshot, size: captureSize)
        let marker = CGPoint(
            x: (localPointer.x - cropRect.minX) / cropRect.width,
            y: (localPointer.y - cropRect.minY) / cropRect.height
        )
        contentView?.marker = marker
        if !hasLoggedFrame {
            hasLoggedFrame = true
            MeowLog.recording.notice(
                "Magnifier captured first stream frame; pixels=\(snapshot.width, privacy: .public)x\(snapshot.height, privacy: .public), panelFrame=\(String(describing: panel.frame), privacy: .public)"
            )
        }
        onFrame?(snapshot, panel.frame, marker, zoom, circular)
    }

    private func positionPanel(near pointer: NSPoint) {
        guard let panel else { return }
        let previousFrame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let preferredSize = CGSize(
            width: CGFloat(settings.magnifierWindowWidth),
            height: CGFloat(settings.magnifierWindowWidth)
                * (settings.magnifierCircular ? 1.0 : 2.0 / 3.0)
        )
        let frame = Self.panelFrame(
            near: pointer,
            visibleFrame: visible,
            preferredSize: preferredSize
        )
        let currentSize = panel.contentRect(forFrameRect: panel.frame).size
        if abs(currentSize.width - frame.width) > 0.5
            || abs(currentSize.height - frame.height) > 0.5 {
            panel.setContentSize(frame.size)
            contentView?.frame = CGRect(origin: .zero, size: frame.size)
        }
        if panel.frame.origin != frame.origin {
            panel.setFrameOrigin(frame.origin)
        }
        if panel.frame != previousFrame {
            onPosition?(panel.frame)
        }
    }

    static func panelFrame(
        near pointer: CGPoint,
        visibleFrame: CGRect,
        preferredSize: CGSize
    ) -> CGRect {
        let marginX = min(8, visibleFrame.width / 4)
        let marginY = min(8, visibleFrame.height / 4)
        let available = visibleFrame.insetBy(dx: marginX, dy: marginY)
        let scale = min(
            1,
            available.width / max(1, preferredSize.width),
            available.height / max(1, preferredSize.height)
        )
        let size = CGSize(
            width: preferredSize.width * scale,
            height: preferredSize.height * scale
        )
        let gap: CGFloat = 12
        let proposed = CGPoint(x: pointer.x + gap, y: pointer.y - size.height - gap)
        return CGRect(
            x: min(max(available.minX, proposed.x), available.maxX - size.width),
            y: min(max(available.minY, proposed.y), available.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func displayID(at point: CGPoint) -> CGDirectDisplayID? {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen.flatMap(displayID(for:))
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func streamCropRect(
        centeredAt pointer: CGPoint,
        in screenFrame: CGRect,
        imageSize: CGSize,
        captureSize: CGSize
    ) -> CGRect {
        let scaleX = imageSize.width / max(1, screenFrame.width)
        let scaleY = imageSize.height / max(1, screenFrame.height)
        let width = min(imageSize.width, max(1, captureSize.width * scaleX))
        let height = min(imageSize.height, max(1, captureSize.height * scaleY))
        let localX = (pointer.x - screenFrame.minX) * scaleX
        let localY = (pointer.y - screenFrame.minY) * scaleY
        return CGRect(
            x: min(max(0, localX - width / 2), imageSize.width - width),
            y: min(max(0, localY - height / 2), imageSize.height - height),
            width: width,
            height: height
        )
    }
}

private struct MagnifierSampleBuffer: @unchecked Sendable {
    // The stream delivers this buffer on DispatchQueue.main, and render consumes it synchronously.
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

private final class MagnifierContentView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var marker = CGPoint(x: 0.5, y: 0.5) {
        didSet { needsDisplay = true }
    }

    var zoom: Int {
        didSet { needsDisplay = true }
    }
    var circular: Bool {
        didSet { needsDisplay = true }
    }

    init(frame: CGRect, zoom: Int, circular: Bool) {
        self.zoom = zoom
        self.circular = circular
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let outline = circular
            ? NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
            : NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16)

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        image?.draw(in: bounds)

        let center = CGPoint(
            x: min(max(0, marker.x), 1) * bounds.width,
            y: min(max(0, marker.y), 1) * bounds.height
        )
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: center.x - 13, y: center.y))
        crosshair.line(to: CGPoint(x: center.x + 13, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 13))
        crosshair.line(to: CGPoint(x: center.x, y: center.y + 13))
        crosshair.lineWidth = 2
        NSColor.black.withAlphaComponent(0.8).setStroke()
        crosshair.stroke()
        crosshair.lineWidth = 1
        NSColor.white.setStroke()
        crosshair.stroke()

        let label = "\(zoom)×" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let labelRect = CGRect(x: circular ? bounds.width * 0.22 : 14, y: 12, width: 58, height: 25)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: labelRect.insetBy(dx: -5, dy: -2), xRadius: 7, yRadius: 7).fill()
        label.draw(in: labelRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        outline.lineWidth = 4
        NSColor.white.withAlphaComponent(0.95).setStroke()
        outline.stroke()
    }
}
