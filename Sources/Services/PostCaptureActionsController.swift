import AppKit
import SwiftUI

enum PostCaptureAction: CaseIterable, Identifiable {
    case copy
    case save
    case edit
    case pin
    case recognizeText
    case translate
    case askAI
    case whiteboard
    case upload

    var id: String {
        switch self {
        case .copy: return "copy"
        case .save: return "save"
        case .edit: return "edit"
        case .pin: return "pin"
        case .recognizeText: return "recognizeText"
        case .translate: return "translate"
        case .askAI: return "askAI"
        case .whiteboard: return "whiteboard"
        case .upload: return "upload"
        }
    }

    var title: String {
        switch self {
        case .copy: return L10n.actionMenuCopy
        case .save: return L10n.postCaptureSave
        case .edit: return L10n.actionMenuEditImage
        case .pin: return L10n.actionMenuPinImage
        case .recognizeText: return L10n.actionMenuRecognizeText
        case .translate: return L10n.actionMenuTranslateImage
        case .askAI: return L10n.actionMenuAskAI
        case .whiteboard: return L10n.whiteboardSendImage
        case .upload: return L10n.uploadAction
        }
    }

    var symbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .save: return "square.and.arrow.down"
        case .edit: return "pencil.and.outline"
        case .pin: return "pin"
        case .recognizeText: return "text.viewfinder"
        case .translate: return "translate"
        case .askAI: return "sparkles"
        case .whiteboard: return "scribble.variable"
        case .upload: return "arrow.up.circle"
        }
    }
}

@MainActor
final class PostCaptureActionsController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<PostCaptureActionsView>?
    private var dismissWorkItem: DispatchWorkItem?
    private var dismissRemaining: TimeInterval?
    private var dismissDeadline: Date?

    func show(
        artifact: CaptureArtifact,
        duration: PostCaptureActionDuration,
        includesUpload: Bool,
        includesWhiteboard: Bool,
        actionHandler: @escaping (PostCaptureAction, CaptureArtifact) -> Void
    ) {
        close()
        dismissRemaining = duration.seconds
        let actions = PostCaptureAction.allCases.filter { action in
            (includesUpload || action != .upload)
                && (includesWhiteboard || action != .whiteboard)
        }

        let view = PostCaptureActionsView(
            artifact: artifact,
            actions: actions,
            onAction: { [weak self] action in
                self?.close()
                actionHandler(action, artifact)
            },
            onClose: { [weak self] in
                self?.close()
            },
            onHoverChanged: { [weak self] isHovering in
                if isHovering {
                    self?.pauseScheduledDismiss()
                } else {
                    self?.scheduleDismiss()
                }
            }
        )
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 202 + CGFloat(actions.count) * 44, height: 86),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting

        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let visibleFrame = screen?.visibleFrame {
            let margin: CGFloat = 28
            let maxWidth = max(260, visibleFrame.width - margin * 2)
            let maxHeight = max(72, visibleFrame.height - margin * 2)
            let targetWidth = min(panel.frame.width, maxWidth)
            let targetHeight = min(panel.frame.height, maxHeight)
            if targetWidth != panel.frame.width || targetHeight != panel.frame.height {
                panel.setContentSize(NSSize(width: targetWidth, height: targetHeight))
            }
            let originX = visibleFrame.midX - panel.frame.width / 2
            let originY = visibleFrame.midY - panel.frame.height / 2
            panel.setFrameOrigin(NSPoint(
                x: max(visibleFrame.minX + margin, min(originX, visibleFrame.maxX - panel.frame.width - margin)),
                y: max(visibleFrame.minY + margin, min(originY, visibleFrame.maxY - panel.frame.height - margin))
            ))
        } else {
            panel.center()
        }

        self.panel = panel
        hostingController = hosting
        panel.orderFrontRegardless()
        scheduleDismiss()
    }

    func close() {
        cancelScheduledDismiss()
        dismissRemaining = nil
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        hostingController = nil
    }

    private func scheduleDismiss() {
        cancelScheduledDismiss()
        guard let dismissRemaining else { return }
        guard dismissRemaining > 0 else {
            close()
            return
        }
        dismissDeadline = Date().addingTimeInterval(dismissRemaining)
        let workItem = DispatchWorkItem { [weak self] in
            self?.close()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissRemaining, execute: workItem)
    }

    private func pauseScheduledDismiss() {
        if let dismissDeadline {
            dismissRemaining = max(0, dismissDeadline.timeIntervalSinceNow)
        }
        cancelScheduledDismiss()
    }

    private func cancelScheduledDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        dismissDeadline = nil
    }
}

private struct PostCaptureActionsView: View {
    let artifact: CaptureArtifact
    let actions: [PostCaptureAction]
    let onAction: (PostCaptureAction) -> Void
    let onClose: () -> Void
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 9) {
            if let image = NSImage(contentsOf: artifact.thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            WindowDragHandle()
                .frame(width: 12, height: 40)

            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(action.title)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.actionCancel)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onHover(perform: onHoverChanged)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setFill()
        for offset in stride(from: CGFloat(12), through: 28, by: 8) {
            NSBezierPath(
                roundedRect: NSRect(x: 4, y: offset, width: 4, height: 4),
                xRadius: 2,
                yRadius: 2
            ).fill()
        }
    }
}
