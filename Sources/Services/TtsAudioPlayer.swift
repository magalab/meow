@preconcurrency import AVFoundation
import Foundation

@MainActor
final class TtsAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var completion: (() -> Void)?
    private var completionBridge: PlaybackCompletionBridge?
    private var playbackID = UUID()
    private(set) var isPaused = false

    init() {
        engine.attach(player)
    }

    func play(_ result: TtsAudioResult, completion: @escaping () -> Void) throws {
        stop(notify: false)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(result.sampleRate),
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(result.samples.count)
        ), let channel = buffer.floatChannelData?[0]
        else {
            throw TtsAudioPlayerError.invalidAudio
        }

        buffer.frameLength = AVAudioFrameCount(result.samples.count)
        result.samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channel.update(from: baseAddress, count: source.count)
        }

        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        if !engine.isRunning {
            try engine.start()
        }
        self.completion = completion
        let playbackID = UUID()
        self.playbackID = playbackID
        isPaused = false
        let bridge = makePlaybackCompletionBridge(player: self, playbackID: playbackID)
        self.completionBridge = bridge
        schedulePlaybackBufferCompletion(on: player, buffer: buffer, bridge: bridge)
        player.play()
    }

    func pause() {
        guard player.isPlaying else { return }
        player.pause()
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        player.play()
        isPaused = false
    }

    func stop() {
        stop(notify: false)
    }

    fileprivate func finishPlayback(for playbackID: UUID) {
        guard self.playbackID == playbackID else { return }
        let completion = self.completion
        self.completion = nil
        completionBridge = nil
        isPaused = false
        completion?()
    }

    private func stop(notify: Bool) {
        playbackID = UUID()
        let completion = completion
        self.completion = nil
        completionBridge = nil
        if player.isPlaying || isPaused {
            player.stop()
        }
        isPaused = false
        if notify {
            completion?()
        }
    }
}

private final class PlaybackCompletionBridge {
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func invoke() {
        handler()
    }
}

private func makePlaybackCompletionBridge(
    player: TtsAudioPlayer,
    playbackID: UUID
) -> PlaybackCompletionBridge {
    PlaybackCompletionBridge {
        DispatchQueue.main.async { [weak player] in
            player?.finishPlayback(for: playbackID)
        }
    }
}

private func schedulePlaybackBufferCompletion(
    on player: AVAudioPlayerNode,
    buffer: AVAudioPCMBuffer,
    bridge: PlaybackCompletionBridge
) {
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
        bridge.invoke()
    }
}

private enum TtsAudioPlayerError: LocalizedError {
    case invalidAudio

    var errorDescription: String? {
        L10n.ttsErrorPlaybackFailed
    }
}
