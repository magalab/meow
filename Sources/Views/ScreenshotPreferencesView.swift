import AppKit
import SwiftUI

struct ScreenshotPreferencesView: View {
    let theme: AppTheme
    @Binding var settings: ScreenshotSettings

    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsScreenshotEnabledTitle,
                subtitle: L10n.prefsScreenshotEnabledSubtitle,
                symbol: "camera.viewfinder",
                theme: theme,
                isOn: $settings.enabled
            )

            if settings.enabled {
                pickerRow(
                    title: L10n.prefsScreenshotDefaultModeTitle,
                    subtitle: L10n.prefsScreenshotDefaultModeSubtitle,
                    symbol: "camera.metering.center.weighted",
                    selection: $settings.defaultCaptureMode,
                    options: ScreenshotCaptureMode.allCases
                ) { $0.displayName }

                PreferenceHotkeyRecorderRow(
                    title: L10n.prefsScreenshotRegionHotkeyTitle,
                    subtitle: L10n.prefsScreenshotRegionHotkeySubtitle,
                    symbol: "viewfinder",
                    theme: theme,
                    keyCode: settings.regionHotkeyKeyCode,
                    modifiers: settings.regionHotkeyModifiers
                ) { keyCode, modifiers in
                    settings.regionHotkeyKeyCode = keyCode
                    settings.regionHotkeyModifiers = modifiers
                }

                PreferenceHotkeyRecorderRow(
                    title: L10n.prefsScreenshotEditHotkeyTitle,
                    subtitle: L10n.prefsScreenshotEditHotkeySubtitle,
                    symbol: "pencil.and.outline",
                    theme: theme,
                    keyCode: settings.editHotkeyKeyCode,
                    modifiers: settings.editHotkeyModifiers
                ) { keyCode, modifiers in
                    settings.editHotkeyKeyCode = keyCode
                    settings.editHotkeyModifiers = modifiers
                }

                PreferenceHotkeyRecorderRow(
                    title: L10n.prefsScreenshotWindowHotkeyTitle,
                    subtitle: L10n.prefsScreenshotWindowHotkeySubtitle,
                    symbol: "macwindow",
                    theme: theme,
                    keyCode: settings.windowHotkeyKeyCode,
                    modifiers: settings.windowHotkeyModifiers
                ) { keyCode, modifiers in
                    settings.windowHotkeyKeyCode = keyCode
                    settings.windowHotkeyModifiers = modifiers
                }

                PreferenceHotkeyRecorderRow(
                    title: L10n.prefsScreenshotDisplayHotkeyTitle,
                    subtitle: L10n.prefsScreenshotDisplayHotkeySubtitle,
                    symbol: "display",
                    theme: theme,
                    keyCode: settings.displayHotkeyKeyCode,
                    modifiers: settings.displayHotkeyModifiers
                ) { keyCode, modifiers in
                    settings.displayHotkeyKeyCode = keyCode
                    settings.displayHotkeyModifiers = modifiers
                }

                pickerRow(
                    title: L10n.prefsScreenshotOutputTitle,
                    subtitle: L10n.prefsScreenshotOutputSubtitle,
                    symbol: "square.and.arrow.down",
                    selection: $settings.outputMode,
                    options: ScreenshotOutputMode.allCases
                ) { $0.displayName }

                pickerRow(
                    title: L10n.prefsScreenshotFormatTitle,
                    subtitle: L10n.prefsScreenshotFormatSubtitle,
                    symbol: "photo",
                    selection: $settings.imageFormat,
                    options: ScreenshotImageFormat.allCases
                ) { $0.displayName }

                if settings.imageFormat == .jpeg {
                    sliderRow
                }

                saveDirectoryRow
                fileNameTemplateRow

                PreferenceToggleRow(
                    title: L10n.prefsScreenshotWindowShadowTitle,
                    subtitle: L10n.prefsScreenshotWindowShadowSubtitle,
                    symbol: "macwindow.on.rectangle",
                    theme: theme,
                    isOn: $settings.includeWindowShadow
                )

                pickerRow(
                    title: L10n.prefsScreenshotHistoryLimitTitle,
                    subtitle: L10n.prefsScreenshotHistoryLimitSubtitle,
                    symbol: "clock.arrow.circlepath",
                    selection: $settings.historyLimit,
                    options: [25, 50, 100, 200, 500]
                ) { String(format: L10n.prefsScreenshotHistoryLimitValue, $0) }

                pickerRow(
                    title: L10n.prefsScreenshotRetentionDaysTitle,
                    subtitle: L10n.prefsScreenshotRetentionDaysSubtitle,
                    symbol: "calendar.badge.clock",
                    selection: $settings.retentionDays,
                    options: [0, 7, 30, 90, 365]
                ) {
                    $0 == 0
                        ? L10n.prefsScreenshotRetentionUnlimited
                        : String(format: L10n.prefsScreenshotRetentionDaysValue, $0)
                }

                pickerRow(
                    title: L10n.prefsScreenshotStorageLimitTitle,
                    subtitle: L10n.prefsScreenshotStorageLimitSubtitle,
                    symbol: "externaldrive",
                    selection: $settings.maxStorageMB,
                    options: [0, 512, 1_024, 2_048, 5_120]
                ) {
                    $0 == 0
                        ? L10n.prefsScreenshotRetentionUnlimited
                        : String(format: L10n.prefsScreenshotStorageLimitValue, $0)
                }

                ocrLanguagesRow

                PreferenceToggleRow(
                    title: L10n.prefsScreenshotSoundTitle,
                    subtitle: L10n.prefsScreenshotSoundSubtitle,
                    symbol: "speaker.wave.2",
                    theme: theme,
                    isOn: $settings.playSound
                )

                postCaptureActionsRow

                PreferenceToggleRow(
                    title: L10n.prefsScreenshotOCRIndexTitle,
                    subtitle: L10n.prefsScreenshotOCRIndexSubtitle,
                    symbol: "text.magnifyingglass",
                    theme: theme,
                    isOn: $settings.automaticallyIndexOCRText
                )
            }
        }
        .animation(.snappy(duration: 0.22), value: settings.enabled)
    }

    private var sliderRow: some View {
        HStack(spacing: 12) {
            icon("slider.horizontal.3")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsScreenshotQualityTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsScreenshotQualitySubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Slider(value: $settings.jpegQuality, in: 0.4...1, step: 0.05)
                .frame(width: 130)
            Text("\(Int(settings.jpegQuality * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
        }
        .screenshotPreferenceRow(palette: palette)
    }

    private var postCaptureActionsRow: some View {
        HStack(spacing: 12) {
            icon("rectangle.and.hand.point.up.left")

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsScreenshotPostActionsTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsScreenshotPostActionsSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if settings.showPostCaptureActions {
                Picker("", selection: $settings.postCaptureActionDuration) {
                    ForEach(PostCaptureActionDuration.allCases) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                .help(L10n.prefsScreenshotPostActionsDurationSubtitle)
            }

            Toggle("", isOn: $settings.showPostCaptureActions)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .animation(.snappy(duration: 0.18), value: settings.showPostCaptureActions)
        .screenshotPreferenceRow(palette: palette)
    }

    private var saveDirectoryRow: some View {
        HStack(spacing: 12) {
            icon("folder")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsScreenshotDirectoryTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(settings.saveDirectory.isEmpty ? L10n.prefsScreenshotDirectoryDefault : settings.saveDirectory)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L10n.prefsScreenshotDirectoryChoose) {
                chooseDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .screenshotPreferenceRow(palette: palette)
    }

    private var fileNameTemplateRow: some View {
        HStack(spacing: 12) {
            icon("textformat")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsScreenshotFileNameTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsScreenshotFileNameSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("", text: $settings.fileNameTemplate)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        }
        .screenshotPreferenceRow(palette: palette)
    }

    private var ocrLanguagesRow: some View {
        HStack(spacing: 12) {
            icon("text.viewfinder")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsScreenshotOCRLanguagesTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.prefsScreenshotOCRLanguagesSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                ForEach(ScreenshotOCRLanguage.allCases) { language in
                    Toggle(
                        language.displayName,
                        isOn: Binding(
                            get: { settings.ocrLanguages.contains(language) },
                            set: { enabled in
                                updateOCRLanguage(language, enabled: enabled)
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
            }
        }
        .screenshotPreferenceRow(palette: palette)
    }

    private func pickerRow<Value: Hashable>(
        title: String,
        subtitle: String,
        symbol: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .screenshotPreferenceRow(palette: palette)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.preferencesAccent)
            .frame(width: 30, height: 30)
            .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.prefsScreenshotDirectoryChoose
        if !settings.saveDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NSString(string: settings.saveDirectory).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url.path
        }
    }

    private func updateOCRLanguage(_ language: ScreenshotOCRLanguage, enabled: Bool) {
        if enabled {
            if !settings.ocrLanguages.contains(language) {
                settings.ocrLanguages.append(language)
            }
        } else if settings.ocrLanguages.count > 1 {
            settings.ocrLanguages.removeAll { $0 == language }
        }
    }
}

private extension View {
    func screenshotPreferenceRow(palette: ThemePalette) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
    }
}
