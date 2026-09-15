import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

struct PreferenceInfoRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

struct PreferenceHotkeyRecorderRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    let keyCode: UInt32
    let modifiers: UInt32
    let onSave: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(isRecording ? L10n.prefsHotkeyRecordingHint : subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isRecording ? L10n.prefsHotkeyRecording : KeyDisplayFormatter.shortcutLabel(keyCode: keyCode, modifiers: modifiers)) {
                startRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isRecording ? .orange : palette.preferencesAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)

            if keyCode == 53 {
                // Esc cancels recording.
                isRecording = false
                stopRecording()
                return nil
            }

            if KeyDisplayFormatter.isModifierOnlyKey(keyCode) {
                return nil
            }

            let modifiers = carbonModifiers(from: event.modifierFlags)
            if modifiers == 0 {
                return nil
            }

            onSave(keyCode, modifiers)
            isRecording = false
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

}

struct PreferenceThemeRow: View {
    @Binding var theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsThemeTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsThemeSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(palette.launcherAccent)
                Circle()
                    .fill(palette.preferencesAccent)
            }
            .frame(width: 28, height: 12)

            Picker("", selection: $theme) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

struct PreferenceDateIconRow: View {
    let theme: AppTheme
    @Binding var style: DateIconStyle
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsDateIconTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsDateIconSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $style) {
                ForEach(DateIconStyle.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

struct PreferenceLanguageRow: View {
    let theme: AppTheme
    @Binding var language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsLanguageTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsLanguageSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}
