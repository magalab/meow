import AVFoundation
import Foundation

public enum RecordingAudioMixerError: Error {
    case invalidConfiguration
}

public enum RecordingAudioMixer {
    public static func mixTracks(in sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let videoTrack = videoTracks.first, audioTracks.count > 1 else {
            return sourceURL
        }
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let duration = videoTimeRange.duration
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingAudioMixerError.invalidConfiguration
        }
        try compositionVideo.insertTimeRange(
            videoTimeRange,
            of: videoTrack,
            at: .zero
        )
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        var mixParameters: [AVMutableAudioMixInputParameters] = []
        for audioTrack in audioTracks {
            guard let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let audioTimeRange = try await audioTrack.load(.timeRange)
            let audioDuration = audioTimeRange.duration
            let insertDuration = min(duration, audioDuration)
            guard insertDuration > .zero else { continue }
            try compositionAudio.insertTimeRange(
                CMTimeRange(start: audioTimeRange.start, duration: insertDuration),
                of: audioTrack,
                at: .zero
            )
            if insertDuration < duration {
                compositionAudio.insertEmptyTimeRange(
                    CMTimeRange(start: insertDuration, duration: duration - insertDuration)
                )
            }
            let parameters = AVMutableAudioMixInputParameters(track: compositionAudio)
            parameters.setVolume(1, at: .zero)
            mixParameters.append(parameters)
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = mixParameters
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecordingAudioMixerError.invalidConfiguration
        }
        exporter.audioMix = mix
        let temporaryURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-mixed")
            .appendingPathExtension(sourceURL.pathExtension)
        let fileType: AVFileType = sourceURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        try await exporter.export(to: temporaryURL, as: fileType)
        _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: temporaryURL)
        return sourceURL
    }
}
