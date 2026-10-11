import SwiftUI

struct RecordingControlView: View {
    @ObservedObject var service: RecordingService
    let onStop: () -> Void
    let onSaveFrame: () -> Void
    let onToggleMagnifier: () -> Void
    let onToggleCamera: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
            Text(time)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            if service.isMicrophoneCapturing {
                HStack(spacing: 4) {
                    Image(systemName: service.isMicrophoneInterrupted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(service.isMicrophoneInterrupted ? .red : .primary)
                    if !service.isMicrophoneInterrupted {
                        ProgressView(value: Double(service.microphoneLevel))
                            .progressViewStyle(.linear)
                            .frame(width: 34)
                    }
                }
                .help(service.isMicrophoneInterrupted
                    ? L10n.recordingMicrophoneInterrupted
                    : L10n.recordingMicrophoneLevel)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(service.isMicrophoneInterrupted
                    ? L10n.recordingMicrophoneInterrupted
                    : L10n.recordingMicrophoneLevel)
                .accessibilityValue(service.isMicrophoneInterrupted
                    ? ""
                    : "\(Int(service.microphoneLevel * 100))%")
            }
            Button {
                service.pauseOrResume()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            Button(action: onSaveFrame) {
                Image(systemName: "photo")
            }
            .buttonStyle(.borderless)
            .help(L10n.recordingSaveFrame)
            .accessibilityLabel(L10n.recordingSaveFrame)
            if service.cameraOverlaySource != nil {
                Button(action: onToggleCamera) {
                    if service.isCameraOverlayChanging {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: service.isCameraOverlayVisible ? "video.fill" : "video.slash")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(service.isCameraOverlayChanging)
                .help(service.isCameraOverlayVisible
                    ? L10n.recordingCameraHide
                    : L10n.recordingCameraShow)
                .accessibilityLabel(service.isCameraOverlayVisible
                    ? L10n.recordingCameraHide
                    : L10n.recordingCameraShow)
            }
            Button(action: onToggleMagnifier) {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help(L10n.recordingMagnifierToggle)
            Button(action: onStop) {
                Image(systemName: "stop.fill").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
    }

    private var isPaused: Bool {
        if case .paused = service.state { return true }
        return false
    }

    private var time: String {
        let total = max(0, Int(service.elapsed))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
