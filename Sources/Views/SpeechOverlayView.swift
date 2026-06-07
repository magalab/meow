import AppKit
import SwiftUI

final class SpeechOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SpeechOverlayController {
    private var panel: SpeechOverlayPanel?
    private var hostingController: NSHostingController<SpeechOverlayView>?
    private weak var service: SpeechRecognitionService?

    func connect(to service: SpeechRecognitionService) {
        self.service = service
        service.onStateChanged = { [weak self] state in
            self?.update(for: state)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func update(for state: SpeechRecognitionState) {
        if state == .idle {
            hide()
            return
        }
        guard let service else { return }
        let panel = createPanelIfNeeded()
        let hosting = NSHostingController(rootView: SpeechOverlayView(service: service))
        hostingController = hosting
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: 320, height: 64))
        position(panel)
        panel.orderFrontRegardless()
    }

    private func createPanelIfNeeded() -> SpeechOverlayPanel {
        if let panel { return panel }
        let panel = SpeechOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 56
        )
        panel.setFrameOrigin(origin)
    }
}

struct SpeechOverlayView: View {
    @ObservedObject var service: SpeechRecognitionService

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .frame(width: 320, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch service.state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 13, height: 13)
                .shadow(color: .red.opacity(0.35), radius: 4)
        case .transcribing, .requestingPermission:
            ProgressView()
                .controlSize(.small)
        case .pasted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 22))
        case .copied:
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 20))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 20))
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 20))
        case .needsModel:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 21))
        case .idle:
            EmptyView()
        }
    }

    private var title: String {
        switch service.state {
        case let .recording(duration):
            return String(format: L10n.speechOverlayRecording, duration)
        case .transcribing:
            return L10n.speechOverlayTranscribing
        case .pasted:
            return L10n.speechOverlayPasted
        case .copied:
            return L10n.speechOverlayCopied
        case .cancelled:
            return L10n.speechOverlayCancelled
        case let .failed(message):
            return message
        case .needsModel:
            return L10n.speechOverlayNeedsModel
        case .requestingPermission:
            return L10n.speechOverlayRequestingPermission
        case .idle:
            return ""
        }
    }

    private var subtitle: String {
        switch service.state {
        case .recording:
            return L10n.speechOverlayReleaseHint
        case .transcribing, .requestingPermission:
            return L10n.speechOverlayCancelHint
        case .copied:
            return L10n.speechOverlayCopiedHint
        case .needsModel:
            return L10n.speechOverlayNeedsModelHint
        default:
            return ""
        }
    }
}
