import AppKit
import SwiftUI

@MainActor
final class PinnedImageController {
    private struct PinnedWindow {
        let panel: NSPanel
        let hostingController: NSHostingController<PinnedImageView>
    }

    private var windows: [UUID: PinnedWindow] = [:]

    func pin(_ imageContent: ImageClipboardContent) {
        let path = imageContent.originalPath ?? imageContent.thumbnailPath
        guard let image = NSImage(contentsOfFile: path) else { return }
        pin(image)
    }

    func pin(_ artifact: CaptureArtifact) {
        guard let image = NSImage(contentsOf: artifact.imageURL) else { return }
        pin(image)
    }

    func closeAll() {
        for entry in windows.values {
            entry.panel.orderOut(nil)
            entry.panel.contentViewController = nil
        }
        windows.removeAll()
    }

    private func pin(_ image: NSImage) {
        let id = UUID()
        let initialSize = fittedSize(for: image.size)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 160, height: 100)
        panel.contentAspectRatio = image.size

        let view = PinnedImageView(
            image: image,
            onClose: { [weak self] in
                self?.close(id)
            },
            onOpacityChanged: { [weak panel] opacity in
                panel?.alphaValue = opacity
            }
        )
        let hosting = NSHostingController(rootView: view)
        panel.contentViewController = hosting
        center(panel)
        panel.orderFrontRegardless()
        windows[id] = PinnedWindow(panel: panel, hostingController: hosting)
    }

    private func close(_ id: UUID) {
        guard let entry = windows.removeValue(forKey: id) else { return }
        entry.panel.orderOut(nil)
        entry.panel.contentViewController = nil
    }

    private func fittedSize(for imageSize: NSSize) -> NSSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: 420, height: 280)
        }
        let maxWidth: CGFloat = 720
        let maxHeight: CGFloat = 540
        let scale = min(1, maxWidth / imageSize.width, maxHeight / imageSize.height)
        return NSSize(
            width: max(160, imageSize.width * scale),
            height: max(100, imageSize.height * scale)
        )
    }

    private func center(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            panel.center()
            return
        }
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.midY - panel.frame.height / 2
            )
        )
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void
    let onOpacityChanged: (Double) -> Void

    @State private var opacity = 1.0
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.04))

            if isHovering {
                HStack(spacing: 8) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11, weight: .semibold))
                    Slider(value: $opacity, in: 0.25...1, step: 0.05)
                        .frame(width: 84)
                        .onChange(of: opacity) { _, value in
                            onOpacityChanged(value)
                        }
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .foregroundStyle(.white)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(10)
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
