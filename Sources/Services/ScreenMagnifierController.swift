import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenMagnifierController {
    static let windowTitle = "Meow Screen Magnifier"

    private let captureSize = CGSize(width: 120, height: 90)
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var timer: Timer?
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]
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
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 225),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.windowTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let imageView = NSImageView(frame: panel.contentView?.bounds ?? .zero)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 16
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView

        self.panel = panel
        self.imageView = imageView
        await update()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.update() }
        }
        panel.orderFrontRegardless()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        imageView = nil
        displays = [:]
        isCapturing = false
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
        let scale = screen.backingScaleFactor
        let localX = (pointer.x - screen.frame.minX) * scale
        let localY = (screen.frame.maxY - pointer.y) * scale
        let screenWidth = screen.frame.width * scale
        let screenHeight = screen.frame.height * scale
        let captureWidth = captureSize.width * scale
        let captureHeight = captureSize.height * scale
        let sourceRect = CGRect(
            x: min(max(0, localX - captureWidth / 2), max(0, screenWidth - captureWidth)),
            y: min(max(0, localY - captureHeight / 2), max(0, screenHeight - captureHeight)),
            width: min(captureWidth, screenWidth),
            height: min(captureHeight, screenHeight)
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = 600
        configuration.height = 450
        configuration.showsCursor = true
        let filter = SCContentFilter(display: display, excludingWindows: [])
        isCapturing = true
        defer { isCapturing = false }
        if let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) {
            imageView?.image = NSImage(cgImage: image, size: captureSize)
        }

        guard let panel else { return }
        let proposed = NSPoint(x: pointer.x + 28, y: pointer.y - panel.frame.height - 28)
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: min(max(visible.minX, proposed.x), visible.maxX - panel.frame.width),
            y: min(max(visible.minY, proposed.y), visible.maxY - panel.frame.height)
        ))
    }
}
