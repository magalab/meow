@preconcurrency import AVFoundation
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

struct RecordingTrimmerView: View {
    let sourceURL: URL
    let theme: AppTheme

    private let minimumTrimInterval = 0.05

    @State private var player = AVPlayer()
    @State private var hasVideo = false
    @State private var previewLoadFailed = false
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var playheadTime: Double = 0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var canvasEnabled = false
    @State private var canvasSettings = RecordingCanvasSettings()
    @State private var selectedCanvasPalette: AppTheme? = nil
    @State private var canvasSourceSize: CGSize?
    @State private var canvasUnavailable = false
    @State private var canvasPreviewTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            previewPane
                .frame(minHeight: 220, maxHeight: .infinity)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 8)

            if canTrim {
                HStack(spacing: 8) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(isPlaying ? L10n.recordingTrimPause : L10n.recordingTrimPreview)
                    .accessibilityLabel(isPlaying ? L10n.recordingTrimPause : L10n.recordingTrimPreview)
                    Text(format(playheadTime))
                        .font(.system(.caption, design: .monospaced))
                    Slider(value: playheadBinding, in: 0...safeDuration, step: minimumTrimInterval) {
                        Text(L10n.recordingTrimPlayhead)
                    } onEditingChanged: { editing in
                        if editing { pausePlayback() }
                    }
                    .labelsHidden()
                    .accessibilityLabel(L10n.recordingTrimPlayhead)
                    Text(format(endTime))
                        .font(.system(.caption, design: .monospaced))
                }
                .frame(height: 26)
                .padding(.bottom, 6)
            }

            trimControls
                .frame(height: 30)

            if hasVideo {
                Divider()
                    .padding(.vertical, 7)
                canvasControls
            }

            Divider()
                .padding(.vertical, 7)

            HStack {
                Text(String(format: L10n.recordingTrimDuration, format(max(0, endTime - startTime))))
                    .foregroundStyle(.secondary)
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.small)
                }
                Button(L10n.recordingTrimExport) {
                    export()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || !canTrim || endTime <= startTime)
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(minWidth: 720, minHeight: 540)
        .task(id: sourceURL) {
            await loadRecording()
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            updatePlayhead()
        }
        .onDisappear {
            canvasPreviewTask?.cancel()
            pausePlayback()
            player.replaceCurrentItem(with: nil)
        }
        .onChange(of: canvasEnabled) { _, _ in updateCanvasPreview() }
        .onChange(of: canvasSettings) { _, _ in updateCanvasPreview() }
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
                pausePlayback()
                let clamped = min(max(0, value), startUpperBound)
                startTime = clamped
                if endTime < clamped + minimumTrimInterval {
                    endTime = min(safeDuration, clamped + minimumTrimInterval)
                }
                seek(to: clamped)
            }
        )
    }

    private var endBinding: Binding<Double> {
        Binding(
            get: {
                min(max(endLowerBound, endTime), safeDuration)
            },
            set: { value in
                pausePlayback()
                endTime = min(max(endLowerBound, value), safeDuration)
                if playheadTime > endTime {
                    seek(to: endTime)
                }
            }
        )
    }

    private var playheadBinding: Binding<Double> {
        Binding(
            get: { min(max(startTime, playheadTime), endTime) },
            set: { seek(to: $0) }
        )
    }

    @ViewBuilder
    private var trimControls: some View {
        if canTrim {
            HStack(spacing: 24) {
                trimSlider(L10n.recordingTrimStart, value: startBinding, time: startTime)
                trimSlider(L10n.recordingTrimEnd, value: endBinding, time: endTime)
            }
        } else {
            Text(previewLoadFailed
                ? L10n.recordingTrimPreviewUnavailable
                : safeDuration > 0
                    ? L10n.recordingTrimTooShort
                    : L10n.recordingTrimLoadingPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trimSlider(_ title: String, value: Binding<Double>, time: Double) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: value, in: 0...safeDuration, step: minimumTrimInterval) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityLabel(title)
            Text(format(time))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var canvasControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L10n.recordingCanvasEnabled, isOn: $canvasEnabled)
                .toggleStyle(.checkbox)
                .disabled(canvasUnavailable)
            if canvasUnavailable {
                Text(L10n.recordingCanvasUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.recordingCanvasAspect)
                        Picker(L10n.recordingCanvasAspect, selection: $canvasSettings.aspect) {
                            ForEach(RecordingCanvasAspect.allCases) { aspect in
                                Text(canvasAspectName(aspect)).tag(aspect)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 118)
                        Text(L10n.recordingCanvasMargin)
                        Slider(value: $canvasSettings.margin, in: 0...0.2)
                        Text("\(Int((canvasSettings.margin * 100).rounded()))%")
                            .frame(width: 36, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Text(L10n.recordingCanvasStyle)
                        Picker(L10n.recordingCanvasStyle, selection: $canvasSettings.backgroundStyle) {
                            ForEach(RecordingCanvasBackgroundStyle.allCases) { style in
                                Text(canvasStyleName(style)).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 105)
                        Text(L10n.recordingCanvasPalette)
                        Picker(L10n.recordingCanvasPalette, selection: Binding(
                            get: { selectedCanvasPalette },
                            set: { applyCanvasPalette($0) }
                        )) {
                            Text(L10n.recordingCanvasPaletteCustom).tag(AppTheme?.none)
                            Text("\(L10n.recordingCanvasPaletteCurrent) · \(theme.displayName)")
                                .tag(Optional(theme))
                            ForEach(AppTheme.allCases.filter { $0 != theme }) { option in
                                Text(option.displayName).tag(Optional(option))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        ColorPicker(L10n.recordingCanvasBackground, selection: canvasColorBinding, supportsOpacity: false)
                            .frame(width: 105)
                        Text(L10n.recordingCanvasCorners)
                        Slider(value: $canvasSettings.cornerRadius, in: 0...0.12)
                        Text("\(Int((canvasSettings.cornerRadius * 100).rounded()))%")
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .controlSize(.small)
                .disabled(!canvasEnabled)
                .opacity(canvasEnabled ? 1 : 0.55)
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if hasVideo {
            RecordingTrimPlayerView(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: canTrim ? "waveform" : "film")
                    .font(.system(size: 44))
                Text(sourceURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func export() {
        guard canTrim, endTime > startTime else { return }
        pausePlayback()
        let selectedStart = startTime
        let selectedEnd = endTime
        let selectedCanvas = canvasEnabled && !canvasUnavailable
        let selectedCanvasSettings = canvasSettings
        let selectedSourceSize = canvasSourceSize
        guard !selectedCanvas || selectedSourceSize != nil else {
            errorMessage = L10n.recordingTrimPreviewUnavailable
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = selectedCanvas || sourceURL.pathExtension.lowercased() == "mov"
            ? [.quickTimeMovie]
            : [.mpeg4Movie]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension()
            .lastPathComponent + " Trimmed." + (selectedCanvas ? "mov" : sourceURL.pathExtension)
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        guard !Self.wouldOverwriteSource(sourceURL: sourceURL, outputURL: outputURL) else {
            errorMessage = L10n.recordingTrimCannotOverwriteSource
            return
        }

        isExporting = true
        Task {
            do {
                let asset = AVURLAsset(url: sourceURL)
                _ = try await asset.load(.duration)
                _ = try await asset.loadTracks(withMediaType: .video)
                _ = try await asset.loadTracks(withMediaType: .audio)
                guard let session = AVAssetExportSession(
                    asset: asset,
                    presetName: selectedCanvas
                        ? AVAssetExportPresetHighestQuality
                        : AVAssetExportPresetPassthrough
                ) else {
                    throw RecordingError.invalidConfiguration
                }
                if selectedCanvas, let selectedSourceSize {
                    session.videoComposition = try await RecordingCanvasComposition.make(
                        asset: asset,
                        sourceSize: selectedSourceSize,
                        settings: selectedCanvasSettings
                    )
                }
                session.timeRange = CMTimeRange(
                    start: CMTime(seconds: selectedStart, preferredTimescale: 600),
                    end: CMTime(seconds: selectedEnd, preferredTimescale: 600)
                )
                let fileType: AVFileType = selectedCanvas || sourceURL.pathExtension.lowercased() == "mov"
                    ? .mov : .mp4
                try await session.export(to: outputURL, as: fileType)
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    static func wouldOverwriteSource(sourceURL: URL, outputURL: URL) -> Bool {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let output = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        if source == output { return true }

        let files = FileManager.default
        guard let sourceAttributes = try? files.attributesOfItem(atPath: source.path),
              let outputAttributes = try? files.attributesOfItem(atPath: output.path),
              let sourceDevice = sourceAttributes[.systemNumber] as? NSNumber,
              let outputDevice = outputAttributes[.systemNumber] as? NSNumber,
              let sourceFile = sourceAttributes[.systemFileNumber] as? NSNumber,
              let outputFile = outputAttributes[.systemFileNumber] as? NSNumber
        else { return false }
        return sourceDevice == outputDevice && sourceFile == outputFile
    }

    private func format(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func loadRecording() async {
        canvasPreviewTask?.cancel()
        pausePlayback()
        player.replaceCurrentItem(with: nil)
        duration = 0
        startTime = 0
        endTime = 0
        playheadTime = 0
        hasVideo = false
        canvasSourceSize = nil
        canvasUnavailable = false
        previewLoadFailed = false
        let asset = AVURLAsset(url: sourceURL)
        do {
            async let loadedDuration = asset.load(.duration)
            async let videoTracks = asset.loadTracks(withMediaType: .video)
            let seconds = try await loadedDuration.seconds
            let tracks = try await videoTracks
            guard !Task.isCancelled else { return }
            duration = seconds.isFinite && seconds > 0 ? seconds : 0
            startTime = 0
            endTime = duration
            playheadTime = 0
            hasVideo = !tracks.isEmpty
            if let videoTrack = tracks.first {
                do {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let transform = try await videoTrack.load(.preferredTransform)
                    let characteristics = try await videoTrack.load(.mediaCharacteristics)
                    let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
                    canvasSourceSize = oriented.size
                    canvasUnavailable = oriented.width <= 0 || oriented.height <= 0
                        || characteristics.contains(.containsHDRVideo)
                        || characteristics.contains(.containsAlphaChannel)
                } catch {
                    canvasUnavailable = true
                }
            }
            player.actionAtItemEnd = .pause
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            updateCanvasPreview()
        } catch {
            guard !Task.isCancelled else { return }
            previewLoadFailed = true
            errorMessage = error.localizedDescription
        }
    }

    private func togglePlayback() {
        guard canTrim else { return }
        if isPlaying {
            pausePlayback()
        } else {
            if playheadTime < startTime || playheadTime >= endTime - minimumTrimInterval / 2 {
                seek(to: startTime)
            }
            player.play()
            isPlaying = true
        }
    }

    private func pausePlayback() {
        player.pause()
        isPlaying = false
    }

    private func seek(to seconds: Double) {
        let clamped = min(max(startTime, seconds), endTime)
        playheadTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func updatePlayhead() {
        guard isPlaying else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        if seconds >= endTime - 0.02 {
            pausePlayback()
            seek(to: endTime)
        } else {
            playheadTime = min(max(startTime, seconds), endTime)
        }
    }

    private func updateCanvasPreview() {
        guard let item = player.currentItem else { return }
        canvasPreviewTask?.cancel()
        pausePlayback()
        if canvasEnabled, !canvasUnavailable, let canvasSourceSize {
            let settings = canvasSettings
            canvasPreviewTask = Task {
                do {
                    let composition = try await RecordingCanvasComposition.make(
                        asset: item.asset,
                        sourceSize: canvasSourceSize,
                        settings: settings
                    )
                    guard !Task.isCancelled, player.currentItem === item,
                          canvasEnabled, canvasSettings == settings else { return }
                    item.videoComposition = composition
                    seek(to: playheadTime)
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            item.videoComposition = nil
            seek(to: playheadTime)
        }
    }

    private func canvasAspectName(_ aspect: RecordingCanvasAspect) -> String {
        switch aspect {
        case .original: return L10n.recordingCanvasOriginal
        case .widescreen: return "16:9"
        case .portrait: return "9:16"
        case .square: return "1:1"
        case .classic: return "4:3"
        }
    }

    private func canvasStyleName(_ style: RecordingCanvasBackgroundStyle) -> String {
        switch style {
        case .solid: return L10n.recordingCanvasStyleSolid
        case .gradient: return L10n.recordingCanvasStyleGradient
        case .stripes: return L10n.recordingCanvasStyleStripes
        case .dots: return L10n.recordingCanvasStyleDots
        case .glow: return L10n.recordingCanvasStyleGlow
        }
    }

    private var canvasColorBinding: Binding<Color> {
        Binding(
            get: { Color(red: canvasSettings.red, green: canvasSettings.green, blue: canvasSettings.blue) },
            set: { color in
                let converted = NSColor(color).usingColorSpace(.sRGB) ?? .black
                selectedCanvasPalette = nil
                var updated = canvasSettings
                updated.red = Double(converted.redComponent)
                updated.green = Double(converted.greenComponent)
                updated.blue = Double(converted.blueComponent)
                updated.accentColor = nil
                canvasSettings = updated
            }
        )
    }

    private func applyCanvasPalette(_ selection: AppTheme?) {
        selectedCanvasPalette = selection
        guard let selection else {
            canvasSettings.accentColor = nil
            return
        }
        let palette = MeowTheme.palette(theme: selection, scheme: colorScheme)
        let base = NSColor(palette.launcherGradient[0]).usingColorSpace(.sRGB) ?? .black
        let accent = NSColor(palette.launcherAccent).usingColorSpace(.sRGB) ?? .black
        var updated = canvasSettings
        updated.red = Double(base.redComponent)
        updated.green = Double(base.greenComponent)
        updated.blue = Double(base.blueComponent)
        updated.accentColor = RecordingCanvasRGB(
            red: Double(accent.redComponent),
            green: Double(accent.greenComponent),
            blue: Double(accent.blueComponent)
        )
        canvasSettings = updated
    }

}

private struct RecordingTrimPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> RecordingTrimPlayerNSView {
        let view = RecordingTrimPlayerNSView()
        view.wantsLayer = true
        view.player = player
        return view
    }

    func updateNSView(_ view: RecordingTrimPlayerNSView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

private final class RecordingTrimPlayerNSView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set { (layer as? AVPlayerLayer)?.player = newValue }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
