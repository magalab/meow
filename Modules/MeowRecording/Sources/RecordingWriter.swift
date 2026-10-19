import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import os
import VideoToolbox
@preconcurrency import ScreenCaptureKit

public enum RecordingWriterFailure: Sendable {
    case invalidConfiguration
    case writerFailed(String)
}

public struct RecordingWriterResult: Sendable {
    public let fileURL: URL
    public let source: RecordingSourceKind
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let codec: RecordingVideoCodec?
    public let hasSystemAudio: Bool
    public let hasMicrophoneAudio: Bool
}

public final class RecordingWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private enum SampleKind {
        case video
        case audio
    }

    private enum SampleSource {
        case video
        case systemAudio
        case microphone

        var kind: SampleKind {
            switch self {
            case .video: return .video
            case .systemAudio, .microphone: return .audio
            }
        }
    }

    public let queue = DispatchQueue(label: "tech.lury.meow.recording.writer", qos: .userInitiated)

    private let outputURL: URL
    private let source: RecordingSourceKind
    private let settings: RecordingSettings
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput?
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let onStreamStopped: @Sendable (Error) -> Void
    private let makeFailure: @Sendable (RecordingWriterFailure) -> Error
    private let logger = Logger(subsystem: "tech.lury.meow", category: "recording")
    private var sessionStarted = false
    private var videoStartPTS: CMTime?
    private var systemAudioStartPTS: CMTime?
    private var microphoneStartPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var lastSystemAudioPTS: CMTime?
    private var lastMicrophonePTS: CMTime?
    private var pausedAt: CMTime?
    private var timeOffset = CMTime.zero
    private var isPaused = false
    private var hasLoggedAppendFailure = false
    private var hasLoggedMagnifierSnapshot = false
    private var hasLoggedMagnifierOutput = false
    private let ciContext = CIContext()
    private let mouseClickCompositor: RecordingMouseClickCompositor
    private let magnifierCompositor: RecordingMagnifierCompositor
    private var latestFrameStorage: CVPixelBuffer?

    public var duration: TimeInterval {
        queue.sync {
            self.durationOnQueue
        }
    }

    public var latestFrame: CGImage? {
        queue.sync {
            guard let pixelBuffer = latestFrameStorage else { return nil }
            return ciContext.createCGImage(
                CIImage(cvPixelBuffer: pixelBuffer),
                from: CGRect(
                    x: 0,
                    y: 0,
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )
        }
    }

    public init(
        outputURL: URL,
        source: RecordingSourceKind,
        configuration: SCStreamConfiguration,
        captureRect: CGRect?,
        highlightColor: RecordingHighlightColor,
        settings: RecordingSettings,
        onStreamStopped: @escaping @Sendable (Error) -> Void,
        makeFailure: @escaping @Sendable (RecordingWriterFailure) -> Error
    ) throws {
        self.outputURL = outputURL
        self.source = source
        self.settings = settings
        self.onStreamStopped = onStreamStopped
        self.makeFailure = makeFailure
        mouseClickCompositor = RecordingMouseClickCompositor(
            captureRect: captureRect,
            enabled: settings.highlightMouseClicks,
            color: highlightColor
        )
        magnifierCompositor = RecordingMagnifierCompositor(captureRect: captureRect)
        let outputFileType: AVFileType
        if source == .systemAudio {
            outputFileType = settings.audioFormat == .aac || settings.audioFormat == .alac
                ? .m4a
                : .caf
        } else if settings.audioMode == .systemAndMicrophone {
            outputFileType = .mov
        } else {
            outputFileType = settings.videoFormat == .mp4 ? .mp4 : .mov
        }
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: outputFileType)

        if source == .systemAudio {
            videoInput = nil
        } else {
            let codec: AVVideoCodecType
            switch settings.videoCodec {
            case .h264: codec = .h264
            case .hevc: codec = .hevc
            case .hevcWithAlpha: codec = .hevcWithAlpha
            }
            let pixels = Double(configuration.width * configuration.height)
            let bitrate = max(500_000, Int(pixels * Double(settings.frameRate) * settings.quality.bitrateMultiplier))
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: settings.frameRate,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
            ]
            var videoSettings: [String: Any] = [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: configuration.width,
                AVVideoHeightKey: configuration.height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            if settings.recordHDR {
                compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel
                videoSettings[AVVideoCompressionPropertiesKey] = compression
                videoSettings[AVVideoColorPropertiesKey] = [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                ]
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw makeFailure(.invalidConfiguration) }
            assetWriter.add(input)
            videoInput = input
        }

        if settings.audioMode.capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: Self.audioSettings(
                    format: source == .systemAudio ? settings.audioFormat : .aac
                )
            )
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw makeFailure(.invalidConfiguration) }
            assetWriter.add(input)
            systemAudioInput = input
        } else {
            systemAudioInput = nil
        }

        if settings.audioMode.capturesMicrophone {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: Self.audioSettings(
                    format: source == .systemAudio ? settings.audioFormat : .aac
                )
            )
            input.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(input) else { throw makeFailure(.invalidConfiguration) }
            assetWriter.add(input)
            microphoneInput = input
        } else {
            microphoneInput = nil
        }
        super.init()
        guard assetWriter.startWriting() else {
            throw makeFailure(.writerFailed(assetWriter.error?.localizedDescription ?? "Unable to start the recording writer."))
        }
    }

    public func setPaused(_ paused: Bool) {
        queue.async {
            self.isPaused = paused
            if paused {
                self.pausedAt = self.currentTimelinePTS()
            }
        }
    }

    public func setMouseClickHighlight(enabled: Bool, color: RecordingHighlightColor) {
        queue.async {
            self.mouseClickCompositor.apply(enabled: enabled, color: color)
        }
    }

    public func recordMouseClick(at point: CGPoint) {
        queue.async {
            self.mouseClickCompositor.recordClick(at: point)
        }
    }

    public func setMagnifierFrame(
        _ image: CGImage?, frame: CGRect, marker: CGPoint, zoom: Int, circular: Bool
    ) {
        queue.async {
            self.magnifierCompositor.setSnapshot(
                image, frame: frame, marker: marker, zoom: zoom, circular: circular
            )
            if image != nil && !self.hasLoggedMagnifierSnapshot {
                self.hasLoggedMagnifierSnapshot = true
                self.logger.notice(
                    "Magnifier snapshot received by writer; renderSucceeded=\(self.magnifierCompositor.isActive, privacy: .public), frame=\(String(describing: frame), privacy: .public)"
                )
            }
        }
    }

    public func setMagnifierPosition(_ frame: CGRect) {
        queue.async {
            self.magnifierCompositor.setFrame(frame)
        }
    }

    public func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        append(sampleBuffer, to: microphoneInput, source: .microphone, establishesSession: videoInput == nil)
    }

    public func finish() async throws -> RecordingWriterResult {
        await withCheckedContinuation { continuation in
            queue.async {
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                self.assetWriter.finishWriting {
                    continuation.resume()
                }
            }
        }
        guard assetWriter.status == .completed else {
            throw makeFailure(.writerFailed(assetWriter.error?.localizedDescription ?? "The recording could not be finalized."))
        }
        var finalURL = outputURL
        if settings.audioMode == .systemAndMicrophone,
           !settings.keepAudioTracksSeparate,
           source != .systemAudio
        {
            do {
                finalURL = try await RecordingAudioMixer.mixTracks(in: outputURL)
            } catch is RecordingAudioMixerError {
                throw makeFailure(.invalidConfiguration)
            }
        }
        return RecordingWriterResult(
            fileURL: finalURL,
            source: source,
            duration: duration,
            width: videoInput == nil ? 0 : Int(videoInput?.outputSettings?[AVVideoWidthKey] as? Int ?? 0),
            height: videoInput == nil ? 0 : Int(videoInput?.outputSettings?[AVVideoHeightKey] as? Int ?? 0),
            codec: videoInput == nil ? nil : settings.videoCodec,
            hasSystemAudio: settings.audioMode.capturesSystemAudio,
            hasMicrophoneAudio: settings.audioMode.capturesMicrophone
        )
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }
        if isPaused { return }
        switch outputType {
        case .screen:
            guard isCompleteScreenFrame(sampleBuffer) else { return }
            latestFrameStorage = sampleBuffer.imageBuffer
            let clickedSample = mouseClickCompositor.composite(sampleBuffer)
            let renderedSample = magnifierCompositor.composite(clickedSample)
            if magnifierCompositor.isActive && !hasLoggedMagnifierOutput {
                hasLoggedMagnifierOutput = true
                let pixelFormat = sampleBuffer.imageBuffer.map(CVPixelBufferGetPixelFormatType) ?? 0
                logger.notice(
                    "Magnifier video composition; applied=\(renderedSample !== clickedSample, privacy: .public), pixelFormat=\(pixelFormat, privacy: .public), overlayFrame=\(String(describing: self.magnifierCompositor.overlayFrame), privacy: .public), captureRect=\(String(describing: self.magnifierCompositor.captureRect), privacy: .public), failure=\(self.magnifierCompositor.lastFailureReason ?? "none", privacy: .public)"
                )
            }
            append(
                renderedSample,
                to: videoInput,
                source: .video,
                establishesSession: true
            )
        case .audio:
            append(sampleBuffer, to: systemAudioInput, source: .systemAudio, establishesSession: videoInput == nil)
        case .microphone:
            append(sampleBuffer, to: microphoneInput, source: .microphone, establishesSession: videoInput == nil)
        @unknown default:
            break
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped(error)
    }

    private func append(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?,
        source: SampleSource,
        establishesSession: Bool
    ) {
        if isPaused { return }
        guard let input, input.isReadyForMoreMediaData else { return }
        let pts = sampleBuffer.presentationTimeStamp
        if establishesSession, !sessionStarted {
            setStartPTS(pts, for: source)
            assetWriter.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
        guard sessionStarted else { return }
        ensureStartPTS(for: source, pts: pts)
        if let pausedAt {
            let timelinePTS = normalizedPTS(for: pts, source: source)
            timeOffset = timeOffset + max(.zero, timelinePTS - pausedAt)
            self.pausedAt = nil
        }
        guard let startPTS = startPTS(for: source) else { return }
        let baseOffset = startPTS + timeOffset
        let adjusted = Self.adjusted(sampleBuffer, by: baseOffset)
        guard let adjusted else { return }
        let adjustedPTS = adjusted.presentationTimeStamp
        if input.append(adjusted) {
            switch source.kind {
            case .video:
                lastVideoPTS = adjustedPTS
            case .audio:
                switch source {
                case .video:
                    break
                case .systemAudio:
                    lastSystemAudioPTS = max(lastSystemAudioPTS ?? .zero, adjustedPTS)
                case .microphone:
                    lastMicrophonePTS = max(lastMicrophonePTS ?? .zero, adjustedPTS)
                }
            }
        } else if !hasLoggedAppendFailure {
            hasLoggedAppendFailure = true
            logger.error(
                "Recording writer rejected a \(String(describing: source), privacy: .public) sample: \(self.assetWriter.error?.localizedDescription ?? "unknown error", privacy: .public)"
            )
        }
    }

    private func currentTimelinePTS() -> CMTime {
        [
            lastVideoPTS,
            lastSystemAudioPTS,
            lastMicrophonePTS,
        ].compactMap { $0 }.max() ?? .zero
    }

    private var durationOnQueue: TimeInterval {
        let lastPTS = currentTimelinePTS()
        return max(0, CMTimeGetSeconds(lastPTS))
    }

    private func normalizedPTS(for sourcePTS: CMTime, source: SampleSource) -> CMTime {
        guard let startPTS = startPTS(for: source) else { return .zero }
        return max(.zero, sourcePTS - startPTS - timeOffset)
    }

    private func setStartPTS(_ pts: CMTime, for source: SampleSource) {
        switch source {
        case .video:
            videoStartPTS = pts
        case .systemAudio:
            systemAudioStartPTS = pts
        case .microphone:
            microphoneStartPTS = pts
        }
    }

    private func startPTS(for source: SampleSource) -> CMTime? {
        switch source {
        case .video:
            return videoStartPTS
        case .systemAudio:
            return systemAudioStartPTS
        case .microphone:
            return microphoneStartPTS
        }
    }

    private func ensureStartPTS(for source: SampleSource, pts: CMTime) {
        guard startPTS(for: source) == nil else { return }
        if source == .systemAudio, videoInput != nil, let videoStartPTS {
            systemAudioStartPTS = videoStartPTS
            return
        }
        let timelineAnchor = currentTimelinePTS()
        setStartPTS(pts - timelineAnchor - timeOffset, for: source)
    }

    private func isCompleteScreenFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let statusValue = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: statusValue) == .complete
        else {
            return false
        }
        return true
    }

    private static func adjusted(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &count
        )
        var timing = [CMSampleTimingInfo](repeating: .init(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: count,
            arrayToFill: &timing,
            entriesNeededOut: &count
        )
        for index in timing.indices {
            timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - offset
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - offset
            }
        }
        var output: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timing,
            sampleBufferOut: &output
        )
        return status == noErr ? output : nil
    }

    private static func audioSettings(format: RecordingAudioFormat) -> [String: Any] {
        let formatID: AudioFormatID
        switch format {
        case .aac: formatID = kAudioFormatMPEG4AAC
        case .alac: formatID = kAudioFormatAppleLossless
        case .flac: formatID = kAudioFormatFLAC
        case .opus: formatID = kAudioFormatOpus
        }
        var settings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
        ]
        if format == .aac || format == .opus {
            settings[AVEncoderBitRateKey] = 192_000
        }
        return settings
    }
}
