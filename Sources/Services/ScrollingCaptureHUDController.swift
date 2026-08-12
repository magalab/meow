import AppKit
import SwiftUI

@MainActor
private final class ScrollingCaptureHUDModel: ObservableObject {
    @Published var progress = ScrollingCaptureProgress.idle
    @Published var preview: NSImage?
    @Published var issue: String?

    let onPauseResume: () -> Void
    let onToggleAutoScroll: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    init(
        onPauseResume: @escaping () -> Void,
        onToggleAutoScroll: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPauseResume = onPauseResume
        self.onToggleAutoScroll = onToggleAutoScroll
        self.onFinish = onFinish
        self.onCancel = onCancel
    }
}
@MainActor
final class ScrollingCaptureHUDController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<ScrollingCaptureHUDView>?
    private var model: ScrollingCaptureHUDModel?

    func show(
        relativeTo captureRect: CGRect,
        on screen: NSScreen,
        onPauseResume: @escaping () -> Void,
        onToggleAutoScroll: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        close()
        let model = ScrollingCaptureHUDModel(
            onPauseResume: onPauseResume,
            onToggleAutoScroll: onToggleAutoScroll,
            onFinish: onFinish,
            onCancel: onCancel
        )
        let view = ScrollingCaptureHUDView(model: model)
        let hosting = NSHostingController(rootView: view)
        let size = NSSize(width: 300, height: 300)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Meow Scrolling Capture"
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        panel.setFrameOrigin(Self.origin(for: size, relativeTo: captureRect, on: screen))

        self.model = model
        self.hostingController = hosting
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func update(progress: ScrollingCaptureProgress) {
        model?.progress = progress
        if case .capturing = progress.state {
            model?.issue = nil
        }
    }

    func update(preview: CGImage) {
        model?.preview = NSImage(
            cgImage: preview,
            size: NSSize(width: preview.width, height: preview.height)
        )
    }

    func showIssue(_ message: String) {
        model?.issue = message
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        hostingController = nil
        model = nil
    }

    private static func origin(for size: NSSize, relativeTo rect: CGRect, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let margin: CGFloat = 14
        let globalRect = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)

        if globalRect.maxX + margin + size.width <= visible.maxX {
            return NSPoint(
                x: globalRect.maxX + margin,
                y: min(visible.maxY - size.height, max(visible.minY, globalRect.midY - size.height / 2))
            )
        }
        if globalRect.minX - margin - size.width >= visible.minX {
            return NSPoint(
                x: globalRect.minX - margin - size.width,
                y: min(visible.maxY - size.height, max(visible.minY, globalRect.midY - size.height / 2))
            )
        }
        let x = min(visible.maxX - size.width, max(visible.minX, globalRect.midX - size.width / 2))
        if globalRect.minY - margin - size.height >= visible.minY {
            return NSPoint(x: x, y: globalRect.minY - margin - size.height)
        }
        return NSPoint(x: x, y: min(visible.maxY - size.height, globalRect.maxY + margin))
    }
}

private struct ScrollingCaptureHUDView: View {
    @ObservedObject var model: ScrollingCaptureHUDModel

    private var isPaused: Bool {
        if case .paused = model.progress.state { return true }
        if case .failed = model.progress.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "scroll")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.scrollingCaptureTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Group {
                if let preview = model.preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .clipped()

            if let issue = model.issue {
                Text(issue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 7) {
                Button(isPaused ? L10n.scrollingCaptureResume : L10n.scrollingCapturePause) {
                    model.onPauseResume()
                }
                .buttonStyle(.bordered)

                Button(
                    model.progress.isAutoScrolling
                        ? L10n.scrollingCaptureManual
                        : L10n.scrollingCaptureAuto
                ) {
                    model.onToggleAutoScroll()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button(L10n.actionCancel) {
                    model.onCancel()
                }
                .buttonStyle(.bordered)

                Button(L10n.scrollingCaptureFinish) {
                    model.onFinish()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var statusText: String {
        let size = model.progress.pixelSize
        if size.width > 0, size.height > 0 {
            return String(
                format: L10n.scrollingCaptureProgress,
                model.progress.stitchedStripCount,
                Int(size.width),
                Int(size.height)
            )
        }
        switch model.progress.state {
        case .preparing:
            return L10n.scrollingCapturePreparing
        case .paused, .failed:
            return L10n.scrollingCapturePaused
        default:
            return L10n.scrollingCaptureScrollHint
        }
    }
}
