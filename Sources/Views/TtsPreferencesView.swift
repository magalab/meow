import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum TtsPreferenceMode {
    case synthesis
    case model
}

struct TtsPreferencesView: View {
    let mode: TtsPreferenceMode
    let theme: AppTheme
    @Binding var settings: TtsSettings
    @ObservedObject var modelStore: TtsModelStore
    @ObservedObject var synthesisService: SpeechSynthesisService

    @Environment(\.colorScheme) private var colorScheme
    @State private var text = ""

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private var normalizedModel: TtsModelKind {
        settings.normalized().model
    }

    var body: some View {
        Group {
            switch mode {
            case .synthesis:
                synthesisContent
            case .model:
                modelContent
            }
        }
    }

    private var synthesisContent: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.ttsInputTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                TtsInputTextView(text: $text, placeholder: L10n.ttsInputPlaceholder)
                    .frame(height: 72)
                    .padding(7)
                    .background(
                        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(palette.surfaceStroke, lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    if normalizedModel != .matchaChineseEnglish {
                        Picker(L10n.ttsVoiceTitle, selection: $settings.voiceID) {
                            ForEach(TtsVoice.available) { voice in
                                Text(voice.displayName).tag(voice.id)
                            }
                        }
                        .frame(maxWidth: 260)
                    } else {
                        Text(L10n.ttsVoiceMatchaSingle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    primaryActionButton

                    if synthesisService.result != nil {
                        Button(playbackButtonTitle) {
                            switch synthesisService.state {
                            case .playing, .paused:
                                synthesisService.pauseOrResume()
                            default:
                                synthesisService.play()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(L10n.ttsStop) {
                            synthesisService.stopPlayback()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(synthesisService.state != .playing && synthesisService.state != .paused)

                        Button(L10n.ttsExport) {
                            exportAudio()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                }

                if case let .synthesizing(progress) = synthesisService.state {
                    ProgressView(value: progress)
                        .tint(palette.preferencesAccent)
                }
            }
            .ttsPanel(palette)
        }
    }

    private var modelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.preferencesAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        palette.iconChipBackground,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(normalizedModel.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(normalizedModel.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(L10n.ttsModelLicense)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Link(
                        L10n.ttsModelSource,
                        destination: normalizedModel.sourceURL
                    )
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                Spacer()
                modelActions
            }

            if case let .downloading(progress) = modelStore.state {
                ProgressView(value: progress)
                    .tint(palette.preferencesAccent)
                Text(String(format: L10n.ttsModelDownloading, progress * 100))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(modelStatusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .ttsPanel(palette)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if synthesisService.state.isGenerating {
            Button(L10n.actionCancel) {
                synthesisService.cancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Button(L10n.ttsGenerate) {
                synthesisService.synthesize(text: text, settings: settings)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(palette.preferencesAccent)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var modelActions: some View {
        switch modelStore.state {
        case .notInstalled, .failed:
            Button(L10n.ttsModelDownload) {
                presentDownloadConfirmation()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(palette.preferencesAccent)
        case .downloading:
            Button(L10n.actionCancel) {
                modelStore.cancelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .installed:
            VStack(alignment: .trailing, spacing: 6) {
                Button(L10n.ttsModelOpenFolder) {
                    modelStore.openModelFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(L10n.ttsModelDelete, role: .destructive) {
                    presentDeleteConfirmation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(synthesisService.state.isGenerating)
            }
        }
    }

    private var playbackButtonTitle: String {
        switch synthesisService.state {
        case .playing:
            return L10n.ttsPause
        case .paused:
            return L10n.ttsResume
        default:
            return L10n.ttsPlay
        }
    }

    private var statusText: String {
        switch synthesisService.state {
        case .idle:
            return modelStore.isInstalled ? L10n.ttsStatusIdle : L10n.ttsStatusNeedsModel
        case .needsModel:
            return L10n.ttsStatusNeedsModel
        case .loadingModel:
            return L10n.ttsStatusLoading
        case let .synthesizing(progress):
            return String(format: L10n.ttsStatusSynthesizing, progress * 100)
        case .ready:
            guard let result = synthesisService.result else { return L10n.ttsStatusReady }
            return String(format: L10n.ttsStatusReadyDuration, result.duration)
        case .playing:
            return L10n.ttsStatusPlaying
        case .paused:
            return L10n.ttsStatusPaused
        case let .failed(message):
            return message
        }
    }

    private var statusColor: Color {
        if case .failed = synthesisService.state {
            return .red
        }
        return .secondary
    }

    private var modelStatusText: String {
        switch modelStore.state {
        case .notInstalled:
            return L10n.ttsModelNotInstalled
        case .downloading:
            return normalizedModel.description
        case .installed:
            return L10n.ttsModelInstalled
        case let .failed(message):
            return message
        }
    }

    private func exportAudio() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "wav") ?? .audio]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportFileName
        if !settings.exportDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.exportDirectory, isDirectory: true)
        } else {
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try synthesisService.exportResult(to: url)
            settings.exportDirectory = url.deletingLastPathComponent().path
        } catch {
            presentError(title: L10n.ttsExportErrorTitle, message: error.localizedDescription)
        }
    }

    private var exportFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Meow TTS \(formatter.string(from: Date())).wav"
    }

    private func presentDownloadConfirmation() {
        NSLog("[Meow] TTS download button tapped")
        let alert = NSAlert()
        alert.messageText = L10n.ttsModelDownloadConfirmTitle
        alert.informativeText = String(
            format: L10n.ttsModelDownloadConfirmMessage,
            normalizedModel.downloadSizeMB
        )
        alert.addButton(withTitle: L10n.ttsModelDownload)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        modelStore.downloadModel()
    }

    private func presentDeleteConfirmation() {
        let alert = NSAlert()
        alert.messageText = L10n.ttsModelDeleteConfirmTitle
        alert.informativeText = L10n.ttsModelDeleteConfirmMessage
        alert.addButton(withTitle: L10n.ttsModelDelete)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        synthesisService.unloadModel()
        modelStore.deleteModel()
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.actionOK)
        _ = alert.runModal()
    }
}

private extension View {
    func ttsPanel(_ palette: ThemePalette) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
    }
}

private struct TtsInputTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> TtsInputTextContainerView {
        let view = TtsInputTextContainerView()
        view.textView.delegate = context.coordinator
        view.textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        view.placeholderTextView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        return view
    }

    func updateNSView(_ nsView: TtsInputTextContainerView, context: Context) {
        if nsView.textView.string != text {
            nsView.textView.string = text
        }
        nsView.placeholderTextView.string = placeholder
        nsView.placeholderTextView.isHidden = !text.isEmpty
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class TtsInputTextContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let placeholderTextView = TtsPassthroughTextView()

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        textView.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width), height: max(0, bounds.height))
        textView.textContainer?.containerSize = NSSize(width: max(0, bounds.width), height: .greatestFiniteMagnitude)
        placeholderTextView.frame = textView.frame
        placeholderTextView.textContainer?.containerSize = textView.textContainer?.containerSize ?? .zero
    }

    private func setup() {
        wantsLayer = true

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)

        placeholderTextView.drawsBackground = false
        placeholderTextView.isEditable = false
        placeholderTextView.isSelectable = false
        placeholderTextView.textColor = .secondaryLabelColor
        placeholderTextView.alphaValue = 0.72
        placeholderTextView.textContainerInset = .zero
        placeholderTextView.textContainer?.lineFragmentPadding = 0
        placeholderTextView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        addSubview(scrollView)
        addSubview(placeholderTextView)
    }
}

private final class TtsPassthroughTextView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
