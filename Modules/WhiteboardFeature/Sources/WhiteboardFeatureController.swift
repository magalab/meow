import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class WhiteboardFeatureController {
    public private(set) var state: WhiteboardFeatureState = .disabled {
        didSet {
            guard oldValue != state else { return }
            onStateChanged?(state)
        }
    }

    public var onStateChanged: ((WhiteboardFeatureState) -> Void)?
    public var onError: ((Error) -> Void)?

    public var captureWindowNumber: CGWindowID? {
        guard state != .disabled, let window else { return nil }
        return CGWindowID(window.windowNumber)
    }

    private var configuration: WhiteboardConfiguration?
    private var store: WhiteboardDocumentStore?
    private var session: WhiteboardSession?
    private var window: WhiteboardDesktopWindow?
    private var canvas: WhiteboardCanvasView?
    private var toolbar: WhiteboardToolbarPanel?
    private var captureSnapshot: CaptureSnapshot?
    private var capturePreparationDepth = 0
    private var displayObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    public init() {}

    public func start(configuration: WhiteboardConfiguration) {
        shutdown()
        WhiteboardLocalization.setLanguage(code: configuration.languageCode)
        self.configuration = configuration
        guard configuration.isEnabled else {
            state = .disabled
            return
        }

        let store = WhiteboardDocumentStore(directory: configuration.storageDirectory)
        let document: WhiteboardDocument
        do {
            document = try store.load()
        } catch {
            onError?(error)
            guard let storeError = error as? WhiteboardDocumentStoreError,
                  case .loadFailedRecovered = storeError
            else {
                return
            }
            document = .empty()
        }
        let session = WhiteboardSession(document: document, store: store)
        session.onError = { [weak self] error in self?.onError?(error) }
        self.store = store
        self.session = session
        startSystemObservation()
        state = .idle

        if configuration.idleVisibility == .visible {
            showBoard()
        }
    }

    public func apply(configuration: WhiteboardConfiguration) {
        guard configuration.isEnabled else {
            shutdown()
            self.configuration = configuration
            return
        }
        guard state != .disabled, let previous = self.configuration else {
            start(configuration: configuration)
            return
        }

        let shouldRebuildWindows = previous.languageCode != configuration.languageCode
            || previous.applicationName != configuration.applicationName
        let wasVisible = window?.isVisible ?? false
        let wasEditing = state == .editing
        WhiteboardLocalization.setLanguage(code: configuration.languageCode)
        self.configuration = configuration
        if previous.storageDirectory != configuration.storageDirectory {
            start(configuration: configuration)
            return
        }
        window?.alphaValue = configuration.editOpacity
        canvas?.updateAppearance(
            surfaceStyle: configuration.surfaceStyle,
            guideStyle: configuration.guideStyle
        )
        if shouldRebuildWindows, window != nil {
            toolbar?.close()
            window?.close()
            toolbar = nil
            canvas = nil
            window = nil
            if wasEditing {
                enterEditing()
            } else if wasVisible {
                showBoard()
            }
        }
        if state == .idle {
            configuration.idleVisibility == .visible ? showBoard() : hideBoard()
        }
    }

    public func toggleEditing() {
        guard state != .disabled, captureSnapshot == nil else { return }
        state == .editing ? leaveEditing() : enterEditing()
    }

    public func showBoard() {
        guard state != .disabled else { return }
        ensureWindows()
        window?.orderFront(nil)
    }

    public func hideBoard() {
        guard state != .disabled else { return }
        if state == .editing, captureSnapshot == nil {
            leaveEditing()
        }
        toolbar?.orderOut(nil)
        window?.orderOut(nil)
    }

    public func saveNow() {
        guard state != .disabled else { return }
        session?.saveNow()
    }

    public func prepareForScreenCapture(_ policy: WhiteboardCapturePolicy) {
        guard state != .disabled else { return }
        if captureSnapshot != nil {
            capturePreparationDepth += 1
            return
        }
        let wasVisible = window?.isVisible ?? false
        captureSnapshot = CaptureSnapshot(state: state, wasVisible: wasVisible)
        capturePreparationDepth = 1
        session?.showsSelection = false
        canvas?.isEditing = false
        toolbar?.orderOut(nil)

        switch policy {
        case .includeContent:
            ensureWindows()
            window?.alphaValue = 1
            window?.suspendInteraction()
            window?.orderFront(nil)
        case .excludeContent:
            window?.orderOut(nil)
        }
    }

    public func restoreAfterScreenCapture() {
        guard let snapshot = captureSnapshot else { return }
        capturePreparationDepth = max(0, capturePreparationDepth - 1)
        guard capturePreparationDepth == 0 else { return }
        captureSnapshot = nil
        session?.showsSelection = true
        window?.alphaValue = configuration?.editOpacity ?? 1

        if snapshot.state == .editing {
            enterEditing()
        } else {
            window?.setEditing(false)
            canvas?.isEditing = false
            state = .idle
            if snapshot.wasVisible {
                window?.orderFront(nil)
            } else {
                window?.orderOut(nil)
            }
        }
    }

    public func importImage(_ image: CGImage, sourceName: String? = nil) {
        guard state != .disabled, let session else { return }
        ensureWindows()
        do {
            try session.addImage(
                image,
                sourceName: sourceName,
                center: canvas?.visibleSceneCenter ?? CGPoint(x: 320, y: 240)
            )
            showBoard()
        } catch {
            onError?(error)
        }
    }

    public func openDocument(_ url: URL) {
        guard state != .disabled, let session, let store else { return }
        do {
            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= 200 * 1_024 * 1_024 else {
                throw NSError(
                    domain: "tech.lury.meow.whiteboard",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: WhiteboardLocalization.text("whiteboard.error.document.too.large"),
                    ]
                )
            }
            let data = try Data(contentsOf: url)
            let decoded = try WhiteboardExcalidrawCodec.decode(data)
            try session.forceSave()
            _ = try store.backupCurrentWorkspace(reason: "before-import")
            try session.replaceDocument(
                decoded.document,
                embeddedImages: decoded.embeddedImages
            )
            showBoard()
        } catch {
            onError?(error)
        }
    }

    public func exportDocument(to url: URL, format: WhiteboardExportFormat) {
        guard state != .disabled, let session else { return }
        do {
            session.saveNow()
            let data: Data
            switch format {
            case .png:
                data = try WhiteboardExporter.png(
                    document: session.document,
                    background: configuration?.outputBackgroundStyle ?? .transparent,
                    image: { session.fullResolutionImage(for: $0) }
                )
            case .svg:
                data = WhiteboardExporter.svg(
                    document: session.document,
                    background: configuration?.outputBackgroundStyle ?? .transparent,
                    imageData: { id in
                        guard let id,
                              let resource = session.document.imageResources.first(where: { $0.id == id })
                        else { return nil }
                        return session.dataForImageResource(resource)
                    }
                )
            case .excalidraw:
                data = try WhiteboardExcalidrawCodec.encode(session.document) {
                    session.dataForImageResource($0)
                }
            }
            try data.write(to: url, options: .atomic)
        } catch {
            onError?(error)
        }
    }

    public func presentImportPanel() {
        guard state != .disabled else { return }
        let panel = NSOpenPanel()
        panel.title = WhiteboardLocalization.text("whiteboard.import.title")
        panel.prompt = WhiteboardLocalization.text("whiteboard.action.import")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "excalidraw") ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if session?.document.elements.isEmpty == false {
            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = WhiteboardLocalization.text("whiteboard.import.confirm.title")
            confirmation.informativeText = WhiteboardLocalization.text("whiteboard.import.confirm.message")
            confirmation.addButton(withTitle: WhiteboardLocalization.text("whiteboard.action.import"))
            confirmation.addButton(withTitle: WhiteboardLocalization.text("whiteboard.action.cancel"))
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        }
        openDocument(url)
    }

    public func presentExportPanel(format: WhiteboardExportFormat) {
        guard state != .disabled else { return }
        let panel = NSSavePanel()
        panel.title = WhiteboardLocalization.text("whiteboard.export.title")
        panel.prompt = WhiteboardLocalization.text("whiteboard.action.export")
        panel.allowedContentTypes = [contentType(for: format)]
        panel.nameFieldStringValue = "whiteboard.\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDocument(to: url, format: format)
    }

    public func shutdown() {
        captureSnapshot = nil
        capturePreparationDepth = 0
        session?.close()
        toolbar?.close()
        window?.close()
        toolbar = nil
        canvas = nil
        window = nil
        session = nil
        store = nil
        configuration = nil
        stopSystemObservation()
        state = .disabled
    }

    private func enterEditing() {
        guard state != .disabled else { return }
        ensureWindows()
        let screen = Self.activeScreen() ?? NSScreen.main
        if let screen {
            window?.fit(to: screen)
            toolbar?.position(on: screen)
        }
        window?.setEditing(true)
        canvas?.isEditing = true
        if let canvas {
            window?.makeFirstResponder(canvas)
        }
        toolbar?.orderFront(nil)
        state = .editing
    }

    private func leaveEditing() {
        guard state == .editing else { return }
        session?.saveNow()
        toolbar?.orderOut(nil)
        canvas?.isEditing = false
        window?.setEditing(false)
        state = .idle
        if configuration?.idleVisibility == .hidden {
            window?.orderOut(nil)
        }
    }

    private func ensureWindows() {
        guard state != .disabled,
              window == nil,
              let session,
              let configuration,
              let screen = Self.activeScreen() ?? NSScreen.main
        else { return }

        let window = WhiteboardDesktopWindow(
            screen: screen,
            applicationName: configuration.applicationName
        )
        window.alphaValue = configuration.editOpacity
        let canvas = WhiteboardCanvasView(
            frame: screen.frame,
            session: session,
            surfaceStyle: configuration.surfaceStyle,
            guideStyle: configuration.guideStyle
        )
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
        let toolbar = WhiteboardToolbarPanel(
            session: session,
            applicationName: configuration.applicationName,
            onImport: { [weak self] in self?.presentImportPanel() },
            onExport: { [weak self] format in self?.presentExportPanel(format: format) },
            onFit: { [weak canvas] in canvas?.fitContent() },
            onFinish: { [weak self] in self?.toggleEditing() }
        )
        toolbar.position(on: screen)
        self.window = window
        self.canvas = canvas
        self.toolbar = toolbar
    }

    private static func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }
    }

    private func startSystemObservation() {
        stopSystemObservation()
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileWindowScreen() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileWindowScreen() }
        }
    }

    private func stopSystemObservation() {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func reconcileWindowScreen() {
        guard state != .disabled, let window else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(window.frame) }
            ?? Self.activeScreen()
            ?? NSScreen.main
        guard let screen else { return }
        window.fit(to: screen)
        if state == .editing {
            toolbar?.position(on: screen)
        }
    }

    private func contentType(for format: WhiteboardExportFormat) -> UTType {
        switch format {
        case .png: return .png
        case .svg: return .svg
        case .excalidraw: return UTType(filenameExtension: "excalidraw") ?? .json
        }
    }
}

private struct CaptureSnapshot {
    let state: WhiteboardFeatureState
    let wasVisible: Bool
}
