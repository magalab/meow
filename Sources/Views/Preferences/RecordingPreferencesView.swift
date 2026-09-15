import AppKit
import SwiftUI

private enum RecordingPreferencePage: String, CaseIterable, Identifiable {
    case videoAudio
    case capture
    case output
    case shortcuts
    case history

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .videoAudio: return L10n.prefsRecordingPageVideoAudio
        case .capture: return L10n.prefsRecordingPageCapture
        case .output: return L10n.prefsRecordingPageOutput
        case .shortcuts: return L10n.prefsRecordingPageShortcuts
        case .history: return L10n.prefsRecordingPageHistory
        }
    }
}

struct RecordingPreferencesView: View {
    let theme: AppTheme
    @Binding var settings: RecordingSettings

    @State private var selectedPage = RecordingPreferencePage.videoAudio
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private var capabilities: RecordingCapabilities {
        RecordingService.capabilities()
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsRecordingEnabledTitle,
                subtitle: L10n.prefsRecordingEnabledSubtitle,
                symbol: "record.circle",
                theme: theme,
                isOn: $settings.enabled
            )

            if settings.enabled {
                Picker("", selection: $selectedPage) {
                    ForEach(RecordingPreferencePage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedPage {
                case .videoAudio:
                    videoAudioPage
                case .capture:
                    capturePage
                case .output:
                    outputPage
                case .shortcuts:
                    shortcutsPage
                case .history:
                    historyPage
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: settings.enabled)
        .animation(.snappy(duration: 0.22), value: selectedPage)
        .onChange(of: settings.videoCodec) { _, codec in
            if codec == .hevcWithAlpha {
                settings.videoFormat = .mov
                settings.recordHDR = false
            }
        }
        .onChange(of: settings.recordHDR) { _, enabled in
            if enabled {
                settings.videoCodec = .hevc
                settings.videoFormat = .mov
                settings.backgroundStyle = .desktop
            }
        }
        .onChange(of: settings.audioMode) { _, mode in
            if mode == .systemAndMicrophone {
                settings.videoFormat = .mov
            }
        }
        .onChange(of: settings.backgroundStyle) { _, style in
            if style == .transparent {
                settings.videoCodec = .hevcWithAlpha
                settings.videoFormat = .mov
                settings.recordHDR = false
            }
        }
    }

    private var videoAudioPage: some View {
        VStack(spacing: 10) {
            if settings.videoFormat == .mov || settings.audioMode == .systemAndMicrophone {
                infoRow(
                    L10n.prefsRecordingMovRequiredTitle,
                    L10n.prefsRecordingMovRequiredSubtitle,
                    "info.circle"
                )
            }

            pickerRow(
                title: L10n.prefsRecordingFormatTitle,
                subtitle: L10n.prefsRecordingFormatSubtitle,
                symbol: "film",
                selection: $settings.videoFormat,
                options: RecordingVideoFormat.allCases
            ) { $0.rawValue.uppercased() }

            pickerRow(
                title: L10n.prefsRecordingCodecTitle,
                subtitle: L10n.prefsRecordingCodecSubtitle,
                symbol: "cpu",
                selection: $settings.videoCodec,
                options: availableCodecs
            ) { codecName($0) }

            if !capabilities.supportsHEVCWithAlpha {
                infoRow(
                    L10n.prefsRecordingAlphaUnavailableTitle,
                    L10n.prefsRecordingAlphaUnavailableSubtitle,
                    "rectangle.on.rectangle.slash"
                )
            }

            pickerRow(
                title: L10n.prefsRecordingQualityTitle,
                subtitle: L10n.prefsRecordingQualitySubtitle,
                symbol: "slider.horizontal.3",
                selection: $settings.quality,
                options: RecordingQuality.allCases
            ) { qualityName($0) }

            pickerRow(
                title: L10n.prefsRecordingFrameRateTitle,
                subtitle: L10n.prefsRecordingFrameRateSubtitle,
                symbol: "speedometer",
                selection: $settings.frameRate,
                options: [24, 30, 60]
            ) { "\($0) FPS" }

            pickerRow(
                title: L10n.prefsRecordingAudioTitle,
                subtitle: L10n.prefsRecordingAudioSubtitle,
                symbol: "waveform",
                selection: $settings.audioMode,
                options: RecordingAudioMode.allCases
            ) { audioName($0) }

            if settings.audioMode.capturesMicrophone {
                microphoneRow
            }

            pickerRow(
                title: L10n.prefsRecordingAudioFormatTitle,
                subtitle: L10n.prefsRecordingAudioFormatSubtitle,
                symbol: "waveform.badge.plus",
                selection: $settings.audioFormat,
                options: RecordingAudioFormat.allCases
            ) { $0.rawValue.uppercased() }

            if settings.audioMode == .systemAndMicrophone {
                toggle(
                    L10n.prefsRecordingSeparateTracksTitle,
                    L10n.prefsRecordingSeparateTracksSubtitle,
                    "timeline.selection",
                    $settings.keepAudioTracksSeparate
                )
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var capturePage: some View {
        VStack(spacing: 10) {
            pickerRow(
                title: L10n.prefsRecordingCountdownTitle,
                subtitle: L10n.prefsRecordingCountdownSubtitle,
                symbol: "timer",
                selection: $settings.countdownSeconds,
                options: [0, 3, 5, 10]
            ) { $0 == 0 ? L10n.recordingNone : String(format: L10n.recordingSeconds, $0) }

            toggle(L10n.prefsRecordingRetinaTitle, L10n.prefsRecordingRetinaSubtitle, "4k.tv", $settings.captureRetinaResolution)
            toggle(L10n.prefsRecordingCursorTitle, L10n.prefsRecordingCursorSubtitle, "cursorarrow", $settings.showCursor)
            toggle(L10n.prefsRecordingMouseHighlightTitle, L10n.prefsRecordingMouseHighlightSubtitle, "cursorarrow.click.2", $settings.highlightMouseClicks)
            toggle(L10n.prefsRecordingMenuBarTitle, L10n.prefsRecordingMenuBarSubtitle, "menubar.rectangle", $settings.includeMenuBar)
            toggle(L10n.prefsRecordingExcludeTitle, L10n.prefsRecordingExcludeSubtitle, "eye.slash", $settings.excludeMeow)
            excludedApplicationsRow
            toggle(L10n.prefsRecordingDesktopTitle, L10n.prefsRecordingDesktopSubtitle, "desktopcomputer", $settings.excludeDesktopIcons)
            toggle(L10n.prefsRecordingSystemUITitle, L10n.prefsRecordingSystemUISubtitle, "switch.2", $settings.excludeSystemOverlays)
            toggle(L10n.prefsRecordingPreventSleepTitle, L10n.prefsRecordingPreventSleepSubtitle, "moon.zzz", $settings.preventSleep)
            toggle(L10n.prefsRecordingFloatingControlsTitle, L10n.prefsRecordingFloatingControlsSubtitle, "record.circle", $settings.showFloatingControls)
            if capabilities.hasCamera {
                cameraRow
            } else {
                infoRow(
                    L10n.prefsRecordingCameraUnavailableTitle,
                    L10n.prefsRecordingCameraUnavailableSubtitle,
                    "video.slash"
                )
            }
            if capabilities.supportsHDR {
                toggle(L10n.prefsRecordingHDRTitle, L10n.prefsRecordingHDRSubtitle, "sun.max", $settings.recordHDR)
            } else {
                infoRow(
                    L10n.prefsRecordingHDRUnavailableTitle,
                    L10n.prefsRecordingHDRUnavailableSubtitle,
                    "sun.max.trianglebadge.exclamationmark"
                )
            }
            backgroundRow
            if !capabilities.hasMobileCaptureDevice {
                infoRow(
                    L10n.prefsRecordingMobileUnavailableTitle,
                    L10n.prefsRecordingMobileUnavailableSubtitle,
                    "iphone.slash"
                )
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var outputPage: some View {
        VStack(spacing: 10) {
            toggle(L10n.prefsRecordingPreviewTitle, L10n.prefsRecordingPreviewSubtitle, "play.rectangle", $settings.showPreview)
            directoryRow
            fileNameRow
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var shortcutsPage: some View {
        VStack(spacing: 10) {
            hotkey(
                L10n.prefsRecordingDisplayHotkeyTitle,
                L10n.prefsRecordingDisplayHotkeySubtitle,
                "display",
                settings.displayHotkeyKeyCode,
                settings.displayHotkeyModifiers
            ) {
                settings.displayHotkeyKeyCode = $0
                settings.displayHotkeyModifiers = $1
            }
            hotkey(
                L10n.prefsRecordingRegionHotkeyTitle,
                L10n.prefsRecordingRegionHotkeySubtitle,
                "viewfinder",
                settings.regionHotkeyKeyCode,
                settings.regionHotkeyModifiers
            ) {
                settings.regionHotkeyKeyCode = $0
                settings.regionHotkeyModifiers = $1
            }
            hotkey(
                L10n.prefsRecordingWindowHotkeyTitle,
                L10n.prefsRecordingWindowHotkeySubtitle,
                "macwindow",
                settings.windowHotkeyKeyCode,
                settings.windowHotkeyModifiers
            ) {
                settings.windowHotkeyKeyCode = $0
                settings.windowHotkeyModifiers = $1
            }
            hotkey(
                L10n.prefsRecordingPauseHotkeyTitle,
                L10n.prefsRecordingPauseHotkeySubtitle,
                "pause.circle",
                settings.pauseHotkeyKeyCode,
                settings.pauseHotkeyModifiers
            ) {
                settings.pauseHotkeyKeyCode = $0
                settings.pauseHotkeyModifiers = $1
            }
            hotkey(
                L10n.prefsRecordingStopHotkeyTitle,
                L10n.prefsRecordingStopHotkeySubtitle,
                "stop.circle",
                settings.stopHotkeyKeyCode,
                settings.stopHotkeyModifiers
            ) {
                settings.stopHotkeyKeyCode = $0
                settings.stopHotkeyModifiers = $1
            }
            hotkey(
                L10n.prefsRecordingFrameHotkeyTitle,
                L10n.prefsRecordingFrameHotkeySubtitle,
                "camera",
                settings.frameHotkeyKeyCode,
                settings.frameHotkeyModifiers
            ) {
                settings.frameHotkeyKeyCode = $0
                settings.frameHotkeyModifiers = $1
            }
            hotkey(
                L10n.prefsRecordingMagnifierHotkeyTitle,
                L10n.prefsRecordingMagnifierHotkeySubtitle,
                "plus.magnifyingglass",
                settings.magnifierHotkeyKeyCode,
                settings.magnifierHotkeyModifiers
            ) {
                settings.magnifierHotkeyKeyCode = $0
                settings.magnifierHotkeyModifiers = $1
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var historyPage: some View {
        VStack(spacing: 10) {
            pickerRow(
                title: L10n.prefsRecordingHistoryLimitTitle,
                subtitle: L10n.prefsRecordingHistoryLimitSubtitle,
                symbol: "clock.arrow.circlepath",
                selection: $settings.historyLimit,
                options: [25, 50, 100, 200, 500]
            ) { "\($0)" }
            pickerRow(
                title: L10n.prefsRecordingRetentionTitle,
                subtitle: L10n.prefsRecordingRetentionSubtitle,
                symbol: "calendar.badge.clock",
                selection: $settings.retentionDays,
                options: [0, 7, 30, 90, 365]
            ) { $0 == 0 ? L10n.recordingUnlimited : String(format: L10n.recordingDays, $0) }
            pickerRow(
                title: L10n.prefsRecordingStorageTitle,
                subtitle: L10n.prefsRecordingStorageSubtitle,
                symbol: "externaldrive",
                selection: $settings.maxStorageMB,
                options: [0, 1_024, 5_120, 10_240, 51_200]
            ) { $0 == 0 ? L10n.recordingUnlimited : "\($0) MB" }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var cameraRow: some View {
        VStack(spacing: 10) {
            row(symbol: "video") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.prefsRecordingCameraTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(L10n.prefsRecordingCameraSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if settings.cameraOverlayEnabled {
                    Picker("", selection: $settings.cameraDeviceID) {
                        Text(L10n.recordingCameraDefault).tag("")
                        ForEach(CameraOverlayController.devices(), id: \.uniqueID) {
                            Text($0.localizedName).tag($0.uniqueID)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                Toggle("", isOn: $settings.cameraOverlayEnabled)
                    .labelsHidden()
            }

            if settings.cameraOverlayEnabled {
                pickerRow(
                    title: L10n.prefsRecordingCameraShapeTitle,
                    subtitle: L10n.prefsRecordingCameraShapeSubtitle,
                    symbol: "rectangle.roundedtop",
                    selection: $settings.cameraOverlayShape,
                    options: RecordingCameraOverlayShape.allCases
                ) { cameraShapeName($0) }
            }
        }
    }

    private var microphoneRow: some View {
        row(symbol: "mic") {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsRecordingMicrophoneTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsRecordingMicrophoneSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $settings.microphoneDeviceID) {
                Text(L10n.recordingMicrophoneDefault).tag("")
                ForEach(RecordingService.microphones(), id: \.uniqueID) {
                    Text($0.localizedName).tag($0.uniqueID)
                }
            }
            .labelsHidden()
            .frame(width: 210)
        }
    }

    private var availableCodecs: [RecordingVideoCodec] {
        var codecs: [RecordingVideoCodec] = [.h264]
        if capabilities.supportsHEVC { codecs.append(.hevc) }
        if capabilities.supportsHEVCWithAlpha { codecs.append(.hevcWithAlpha) }
        return codecs
    }

    private func infoRow(
        _ title: String,
        _ subtitle: String,
        _ symbol: String
    ) -> some View {
        PreferenceInfoRow(title: title, subtitle: subtitle, symbol: symbol, theme: theme)
    }

    private var directoryRow: some View {
        row(symbol: "folder") {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsRecordingDirectoryTitle).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(settings.saveDirectory.isEmpty ? L10n.prefsRecordingDirectoryDefault : settings.saveDirectory)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.prefsScreenshotDirectoryChoose) { chooseDirectory() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var fileNameRow: some View {
        row(symbol: "textformat") {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsRecordingFileNameTitle).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsRecordingFileNameSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("", text: $settings.fileNameTemplate)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        }
    }

    private var excludedApplicationsRow: some View {
        row(symbol: "app.badge.checkmark") {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsRecordingExcludedAppsTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsRecordingExcludedAppsSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(
                "com.example.app",
                text: Binding(
                    get: { settings.excludedApplicationBundleIDs.joined(separator: ", ") },
                    set: {
                        settings.excludedApplicationBundleIDs = $0
                            .split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }
    }

    private var backgroundRow: some View {
        row(symbol: "rectangle.fill") {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsRecordingBackgroundTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsRecordingBackgroundSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if settings.backgroundStyle == .solidColor {
                TextField("#1C1C1E", text: $settings.backgroundColorHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            Picker("", selection: $settings.backgroundStyle) {
                ForEach(RecordingBackgroundStyle.allCases) {
                    Text(backgroundName($0)).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
    }

    private func toggle(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ binding: Binding<Bool>
    ) -> some View {
        PreferenceToggleRow(title: title, subtitle: subtitle, symbol: symbol, theme: theme, isOn: binding)
    }

    private func hotkey(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ keyCode: UInt32,
        _ modifiers: UInt32,
        onSave: @escaping (UInt32, UInt32) -> Void
    ) -> some View {
        PreferenceHotkeyRecorderRow(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            theme: theme,
            keyCode: keyCode,
            modifiers: modifiers,
            onSave: onSave
        )
    }

    private func pickerRow<Value: Hashable>(
        title: String,
        subtitle: String,
        symbol: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        row(symbol: symbol) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 170)
        }
    }

    private func row<Content: View>(
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9))
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.surfaceStroke))
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url.path
        }
    }

    private func codecName(_ codec: RecordingVideoCodec) -> String {
        switch codec {
        case .h264: return "H.264"
        case .hevc: return "H.265 / HEVC"
        case .hevcWithAlpha: return "HEVC Alpha"
        }
    }

    private func backgroundName(_ style: RecordingBackgroundStyle) -> String {
        switch style {
        case .desktop: return L10n.recordingBackgroundDesktop
        case .transparent: return L10n.recordingBackgroundTransparent
        case .solidColor: return L10n.recordingBackgroundSolid
        }
    }

    private func cameraShapeName(_ shape: RecordingCameraOverlayShape) -> String {
        switch shape {
        case .rectangle: return L10n.recordingCameraShapeRectangle
        case .rounded: return L10n.recordingCameraShapeRounded
        case .circle: return L10n.recordingCameraShapeCircle
        }
    }

    private func qualityName(_ quality: RecordingQuality) -> String {
        switch quality {
        case .compact: return L10n.recordingQualityCompact
        case .balanced: return L10n.recordingQualityBalanced
        case .high: return L10n.recordingQualityHigh
        }
    }

    private func audioName(_ mode: RecordingAudioMode) -> String {
        switch mode {
        case .none: return L10n.recordingAudioNone
        case .system: return L10n.recordingAudioSystem
        case .microphone: return L10n.recordingAudioMicrophone
        case .systemAndMicrophone: return L10n.recordingAudioBoth
        }
    }
}
