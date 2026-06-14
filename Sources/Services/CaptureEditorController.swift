import AppKit
import SwiftUI

@MainActor
final class CaptureEditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hostingController: NSHostingController<CaptureEditorView>?
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var isFinishing = false

    func present(source: CGImage) async -> CGImage? {
        cancel()
        isFinishing = false

        return await withCheckedContinuation {
            (continuation: CheckedContinuation<CGImage?, Never>) in
            self.continuation = continuation
            let model = CaptureEditorModel(
                sourceSize: CGSize(width: source.width, height: source.height)
            )
            let view = CaptureEditorView(
                source: source,
                model: model,
                onCancel: { [weak self] in
                    self?.finish(nil)
                },
                onFinish: { [weak self] image in
                    self?.finish(image)
                }
            )
            let hosting = NSHostingController(rootView: view)
            hostingController = hosting

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.delegate = self
            window.title = L10n.editorTitle
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.minSize = NSSize(width: 760, height: 620)
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func cancel() {
        finish(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil, closeWindow: false)
    }

    private func finish(_ image: CGImage?, closeWindow: Bool = true) {
        guard !isFinishing else { return }
        guard continuation != nil || window != nil else { return }
        isFinishing = true

        if closeWindow {
            window?.delegate = nil
            window?.close()
        }
        window = nil
        hostingController = nil

        let pending = continuation
        continuation = nil
        pending?.resume(returning: image)
    }
}
