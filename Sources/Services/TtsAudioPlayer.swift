@preconcurrency import AVFoundation
import Foundation

@MainActor
final class TtsAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var completion: (() -> Void)?
    private var completionBridge: PlaybackCompletionBridge?
    private var playbackID = UUID()
    private var streamingSampleRate: Int?
    private(set) var isPaused = false
    private(set) var isStreaming = false

    init() {
        engine.attach(player)
    }

    func play(_ result: TtsAudioResult, completion: @escaping () -> Void) throws {
        try startStreaming(sampleRate: result.sampleRate, completion: completion)
        try append(
            samples: result.samples,
            sampleRate: result.sampleRate,
            isFinal: true
        )
    }

    func startStreaming(
        sampleRate: Int,
        completion: @escaping () -> Void
    ) throws {
        stop(notify: false)
        guard sampleRate > 0 else {
            throw TtsAudioPlayerError.invalidAudio
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )
        else {
            throw TtsAudioPlayerError.invalidAudio
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
        streamingSampleRate = sampleRate
        isPaused = false
        isStreaming = true
        let bridge = makePlaybackCompletionBridge(player: self, playbackID: playbackID)
        self.completionBridge = bridge
    }

    func append(
        samples: [Float],
        sampleRate: Int,
        isFinal: Bool
    ) throws {
        guard isStreaming, streamingSampleRate == sampleRate,
              let bridge = completionBridge,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(sampleRate),
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ), let channel = buffer.floatChannelData?[0]
        else {
            throw TtsAudioPlayerError.invalidAudio
        }
        guard !samples.isEmpty else {
            if isFinal {
                bridge.invoke()
            }
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channel.update(from: baseAddress, count: source.count)
        }
        schedulePlaybackBufferCompletion(
            on: player,
            buffer: buffer,
            bridge: bridge,
            isFinal: isFinal
        )
        if !player.isPlaying {
            player.play()
        }
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
        streamingSampleRate = nil
        isStreaming = false
        isPaused = false
        completion?()
    }

    private func stop(notify: Bool) {
        playbackID = UUID()
        let completion = completion
        self.completion = nil
        completionBridge = nil
        streamingSampleRate = nil
        isStreaming = false
        if player.isPlaying || isPaused || isStreaming {
            player.stop()
        }
        isPaused = false
        if notify {
            completion?()
        }
    }
}

private final class PlaybackCompletionBridge: @unchecked Sendable {
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
    bridge: PlaybackCompletionBridge,
    isFinal: Bool
) {
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
        if isFinal {
            bridge.invoke()
        }
    }
}

private enum TtsAudioPlayerError: LocalizedError {
    case invalidAudio

    var errorDescription: String? {
        L10n.ttsErrorPlaybackFailed
    }
}
