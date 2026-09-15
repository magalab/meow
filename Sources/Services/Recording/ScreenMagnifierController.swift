import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenMagnifierController {
    static let windowTitle = "Meow Screen Magnifier"

    private let captureSize = CGSize(width: 180, height: 120)
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var timer: Timer?
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]
    private var excludedWindows: [SCWindow] = []
    private var isCapturing = false

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() async {
        if isVisible {
            stop()
        } else {
            try? await start()
        }
    }

    func start() async throws {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
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

        let imageView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView

        self.panel = panel
        self.imageView = imageView
        positionPanel(near: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(80))
        try await refreshShareableContent()
        await update()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        imageView = nil
        displays = [:]
        excludedWindows = []
        isCapturing = false
    }

    private func refreshShareableContent() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
        excludedWindows = content.windows.filter { $0.title == Self.windowTitle }
    }

    private func update() async {
        guard !isCapturing else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let screen,
              let displayNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber,
              let display = displays[CGDirectDisplayID(displayNumber.uint32Value)]
        else { return }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = Self.sourceRect(
            centeredAt: pointer,
            in: screen.frame,
            captureSize: captureSize
        )
        configuration.width = 720
        configuration.height = 480
        configuration.showsCursor = true
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        isCapturing = true
        defer { isCapturing = false }
        if let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) {
            imageView?.image = NSImage(cgImage: image, size: captureSize)
        }

        positionPanel(near: pointer)
    }

    private func positionPanel(near pointer: NSPoint) {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let proposed = NSPoint(x: pointer.x + 28, y: pointer.y - panel.frame.height - 28)
        panel.setFrameOrigin(NSPoint(
            x: min(max(visible.minX, proposed.x), visible.maxX - panel.frame.width),
            y: min(max(visible.minY, proposed.y), visible.maxY - panel.frame.height)
        ))
    }

    static func sourceRect(
        centeredAt pointer: CGPoint,
        in screenFrame: CGRect,
        captureSize: CGSize
    ) -> CGRect {
        let localX = pointer.x - screenFrame.minX
        let localY = screenFrame.maxY - pointer.y
        let width = min(captureSize.width, screenFrame.width)
        let height = min(captureSize.height, screenFrame.height)
        return CGRect(
            x: min(max(0, localX - width / 2), max(0, screenFrame.width - width)),
            y: min(max(0, localY - height / 2), max(0, screenFrame.height - height)),
            width: width,
            height: height
        )
    }
}
