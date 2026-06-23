import AppKit
import AVFoundation

@MainActor
final class CameraOverlayController {
    static let windowTitle = "Meow Camera Overlay"

    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var frameObserver: NSObjectProtocol?

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    func start(deviceID: String, shape: RecordingCameraOverlayShape, on screen: NSScreen?) async throws {
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

        let contentSize = Self.initialSize(for: shape)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
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
        panel.minSize = Self.minSize(for: shape)
        panel.maxSize = Self.maxSize(for: shape)
        if shape == .circle {
            panel.contentAspectRatio = NSSize(width: 1, height: 1)
        }

        let view = NSView(frame: panel.contentView?.bounds ?? .zero)
        view.wantsLayer = true
        view.layer?.cornerRadius = Self.cornerRadius(for: shape, size: view.bounds.size)
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        panel.contentView = view
        view.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: view,
            queue: .main
        ) { [weak view] _ in
            Task { @MainActor [weak view] in
                view?.layer?.cornerRadius = Self.cornerRadius(for: shape, size: view?.bounds.size ?? .zero)
            }
        }

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

    private static func cornerRadius(for shape: RecordingCameraOverlayShape, size: CGSize) -> CGFloat {
        switch shape {
        case .rectangle:
            return 0
        case .rounded:
            return 18
        case .circle:
            return min(size.width, size.height) / 2
        }
    }

    private static func initialSize(for shape: RecordingCameraOverlayShape) -> NSSize {
        shape == .circle ? NSSize(width: 220, height: 220) : NSSize(width: 240, height: 180)
    }

    private static func minSize(for shape: RecordingCameraOverlayShape) -> NSSize {
        shape == .circle ? NSSize(width: 140, height: 140) : NSSize(width: 160, height: 120)
    }

    private static func maxSize(for shape: RecordingCameraOverlayShape) -> NSSize {
        shape == .circle ? NSSize(width: 520, height: 520) : NSSize(width: 640, height: 480)
    }

    func stop() {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
        frameObserver = nil
        session?.stopRunning()
        session = nil
        previewLayer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
