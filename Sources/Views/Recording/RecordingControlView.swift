import SwiftUI

struct RecordingControlView: View {
    @ObservedObject var service: RecordingService
    let onStop: () -> Void
    let onSaveFrame: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
            Text(time)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Button {
                service.pauseOrResume()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)
            Button(action: onSaveFrame) {
                Image(systemName: "camera")
            }
            .buttonStyle(.borderless)
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
