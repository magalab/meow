import AppKit
import AVFoundation

@MainActor
final class CameraOverlayController {
    static let windowTitle = "Meow Camera Overlay"

    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var contentView: CameraOverlayContentView?
    private var frameObserver: NSObjectProtocol?
    private var shape: RecordingCameraOverlayShape = .rounded

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
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = Self.minSize(for: shape)
        panel.maxSize = Self.maxSize(for: shape)
        if shape == .circle {
            panel.contentAspectRatio = NSSize(width: 1, height: 1)
        }

        let view = CameraOverlayContentView(frame: panel.contentView?.bounds ?? .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = Self.cornerRadius(for: shape, size: view.bounds.size)
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.onShapeSelected = { [weak self] shape in
            self?.apply(shape: shape)
        }
        view.selectedShape = shape
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.clear.cgColor
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        panel.contentView = view
        view.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: view,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let contentView = self.contentView else { return }
                contentView.layer?.cornerRadius = Self.cornerRadius(for: self.shape, size: contentView.bounds.size)
                contentView.layoutShapeControls()
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
        self.contentView = view
        self.shape = shape
        previewLayer = layer
        session.startRunning()
        panel.orderFrontRegardless()
    }

    private func apply(shape: RecordingCameraOverlayShape) {
        guard let panel, let contentView else { return }
        self.shape = shape
        contentView.selectedShape = shape
        panel.minSize = Self.minSize(for: shape)
        panel.maxSize = Self.maxSize(for: shape)
        if shape == .circle {
            let size = min(panel.frame.width, panel.frame.height)
            panel.setFrame(
                NSRect(
                    x: panel.frame.midX - size / 2,
                    y: panel.frame.midY - size / 2,
                    width: size,
                    height: size
                ),
                display: true,
                animate: false
            )
            panel.contentAspectRatio = NSSize(width: 1, height: 1)
        } else {
            panel.contentAspectRatio = NSSize(width: 0, height: 0)
        }
        contentView.layer?.cornerRadius = Self.cornerRadius(for: shape, size: contentView.bounds.size)
        contentView.layoutShapeControls()
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
        contentView = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class CameraOverlayContentView: NSView {
    var onShapeSelected: ((RecordingCameraOverlayShape) -> Void)?
    var selectedShape: RecordingCameraOverlayShape = .rounded {
        didSet { updateSelection() }
    }

    private let controls = NSStackView()
    private var trackingAreaRef: NSTrackingArea?
    private var buttons: [RecordingCameraOverlayShape: NSButton] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupControls()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupControls()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setControlsVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setControlsVisible(false)
    }

    override func layout() {
        super.layout()
        layoutShapeControls()
    }

    func layoutShapeControls() {
        let size = controls.fittingSize
        controls.frame = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height - 10,
            width: size.width,
            height: size.height
        )
    }

    private func setupControls() {
        controls.orientation = .horizontal
        controls.spacing = 4
        controls.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.46).cgColor
        controls.layer?.cornerRadius = 9
        controls.alphaValue = 0

        for shape in RecordingCameraOverlayShape.allCases {
            let button = NSButton(
                image: Self.image(for: shape),
                target: self,
                action: #selector(selectShape(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(shape.rawValue)
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = .white
            button.toolTip = Self.tooltip(for: shape)
            button.setButtonType(.momentaryChange)
            button.frame.size = NSSize(width: 24, height: 24)
            buttons[shape] = button
            controls.addArrangedSubview(button)
        }
        addSubview(controls)
        updateSelection()
    }

    private func setControlsVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            controls.animator().alphaValue = visible ? 1 : 0
        }
    }

    @objc private func selectShape(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let shape = RecordingCameraOverlayShape(rawValue: rawValue)
        else { return }
        onShapeSelected?(shape)
    }

    private func updateSelection() {
        for (shape, button) in buttons {
            button.contentTintColor = shape == selectedShape ? .systemYellow : .white
        }
    }

    private static func image(for shape: RecordingCameraOverlayShape) -> NSImage {
        let symbolName: String
        switch shape {
        case .rectangle: symbolName = "rectangle"
        case .rounded: symbolName = "rectangle.roundedtop"
        case .circle: symbolName = "circle"
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip(for: shape)) ?? NSImage()
    }

    private static func tooltip(for shape: RecordingCameraOverlayShape) -> String {
        switch shape {
        case .rectangle: return L10n.recordingCameraShapeRectangle
        case .rounded: return L10n.recordingCameraShapeRounded
        case .circle: return L10n.recordingCameraShapeCircle
        }
    }
}
