import AppKit
import AVFoundation

@MainActor
final class CameraOverlayController {
    static let windowTitle = "Meow Camera Overlay"

    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    func start(deviceID: String, on screen: NSScreen?) async throws {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }
        guard granted else { throw RecordingError.permissionDenied }

        let device = Self.devices().first { $0.uniqueID == deviceID }
            ?? AVCaptureDevice.default(for: .video)
        guard let device else { throw RecordingError.sourceUnavailable }

        stop()
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw RecordingError.invalidConfiguration }
        session.addInput(input)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.windowTitle
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .black
        panel.hasShadow = true
        panel.minSize = NSSize(width: 160, height: 120)
        panel.maxSize = NSSize(width: 640, height: 480)

        let view = NSView(frame: panel.contentView?.bounds ?? .zero)
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.masksToBounds = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        panel.contentView = view

        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - panel.frame.width - 24,
                y: frame.minY + 24
            ))
        } else {
            panel.center()
        }

        self.session = session
        self.panel = panel
        previewLayer = layer
        session.startRunning()
        panel.orderFrontRegardless()
    }

    func stop() {
        session?.stopRunning()
        session = nil
        previewLayer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
