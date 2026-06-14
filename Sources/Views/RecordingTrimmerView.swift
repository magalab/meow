import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct RecordingTrimmerView: View {
    let sourceURL: URL

    private let minimumTrimInterval = 0.05

    @State private var previewImage: NSImage?
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            previewPane
                .frame(minHeight: 320)
                .background(.black)

            VStack(spacing: 8) {
                if canTrim {
                    HStack {
                        Text(format(startTime))
                            .font(.system(.caption, design: .monospaced))
                        Slider(value: startBinding, in: 0...startUpperBound, step: minimumTrimInterval) {
                            Text(L10n.recordingTrimStart)
                        }
                    }
                    HStack {
                        Text(format(endTime))
                            .font(.system(.caption, design: .monospaced))
                        Slider(value: endBinding, in: endLowerBound...safeDuration, step: minimumTrimInterval) {
                            Text(L10n.recordingTrimEnd)
                        }
                    }
                } else {
                    Text(L10n.recordingTrimStaticPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(String(format: L10n.recordingTrimDuration, format(max(0, endTime - startTime))))
                    .foregroundStyle(.secondary)
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.small)
                }
                Button(L10n.recordingTrimPreview) {
                    NSWorkspace.shared.open(sourceURL)
                }
                Button(L10n.recordingTrimExport) {
                    export()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || !canTrim || endTime <= startTime)
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 500)
        .task {
            let asset = AVURLAsset(url: sourceURL)
            do {
                let seconds = try await asset.load(.duration).seconds
                duration = seconds.isFinite && seconds > minimumTrimInterval ? seconds : 0
                startTime = 0
                endTime = duration
                await loadPreviewFrame(at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert(L10n.recordingErrorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.actionOK) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var safeDuration: Double {
        duration.isFinite && duration > 0 ? duration : 0
    }

    private var canTrim: Bool {
        safeDuration > minimumTrimInterval
    }

    private var startUpperBound: Double {
        max(0, safeDuration - minimumTrimInterval)
    }

    private var endLowerBound: Double {
        min(safeDuration, max(minimumTrimInterval, startTime + minimumTrimInterval))
    }

    private var startBinding: Binding<Double> {
        Binding(
            get: {
                min(max(0, startTime), startUpperBound)
            },
            set: { value in
                let clamped = min(max(0, value), startUpperBound)
                startTime = clamped
                if endTime < clamped + minimumTrimInterval {
                    endTime = min(safeDuration, clamped + minimumTrimInterval)
                }
                Task { await loadPreviewFrame(at: clamped) }
            }
        )
    }

    private var endBinding: Binding<Double> {
        Binding(
            get: {
                min(max(endLowerBound, endTime), safeDuration)
            },
            set: { value in
                endTime = min(max(endLowerBound, value), safeDuration)
            }
        )
    }

    @ViewBuilder
    private var previewPane: some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 44))
                Text(sourceURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text(L10n.recordingTrimStaticPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func export() {
        guard canTrim, endTime > startTime else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = sourceURL.pathExtension.lowercased() == "mov"
            ? [.quickTimeMovie]
            : [.mpeg4Movie]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension()
            .lastPathComponent + " Trimmed." + sourceURL.pathExtension
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isExporting = true
        Task {
            do {
                let asset = AVURLAsset(url: sourceURL)
                guard let session = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetPassthrough
                ) else {
                    throw RecordingError.invalidConfiguration
                }
                session.timeRange = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 600),
                    end: CMTime(seconds: endTime, preferredTimescale: 600)
                )
                let fileType: AVFileType = sourceURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
                try await session.export(to: outputURL, as: fileType)
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func format(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    @MainActor
    private func loadPreviewFrame(at seconds: Double) async {
        guard seconds.isFinite else {
            previewImage = nil
            return
        }
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        do {
            let image = try await generator.image(
                at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            ).image
            previewImage = NSImage(cgImage: image, size: .zero)
        } catch {
            previewImage = nil
        }
    }
}
