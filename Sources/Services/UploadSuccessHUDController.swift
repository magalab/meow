import AppKit
import SwiftUI

@MainActor
final class UploadSuccessHUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(filename: String, relativeTo statusButton: NSButton?) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let view = UploadSuccessHUD(filename: filename)
        let hosting = NSHostingController(rootView: view)
        let size = NSSize(width: 280, height: 64)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = hosting
        panel.setFrameOrigin(origin(for: size, relativeTo: statusButton))
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
            if self?.panel === panel {
                self?.panel = nil
            }
        }
    }

    private func origin(for size: NSSize, relativeTo statusButton: NSButton?) -> NSPoint {
        let anchor: NSPoint
        if let button = statusButton, let window = button.window {
            let frame = window.convertToScreen(button.frame)
            anchor = NSPoint(x: frame.midX, y: frame.minY - 8)
        } else {
            anchor = NSEvent.mouseLocation
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let x = min(max(visible.minX + 8, anchor.x - size.width / 2), visible.maxX - size.width - 8)
        let y = max(visible.minY + 8, anchor.y - size.height)
        return NSPoint(x: x, y: y)
    }
}

private struct UploadSuccessHUD: View {
    let filename: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.uploadSucceeded)
                    .font(.system(size: 13, weight: .semibold))
                Text(filename)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 280, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
