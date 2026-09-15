import SwiftUI

struct KeepAwakePreferencesView: View {
    let theme: AppTheme
    @Binding var settings: KeepAwakeSettings
    @ObservedObject var service: KeepAwakeService
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.keepAwakeEnabledTitle,
                subtitle: L10n.keepAwakeEnabledSubtitle,
                symbol: "moon.zzz",
                theme: theme,
                isOn: $settings.enabled
            )

            if settings.enabled {
                pickerRow(
                    title: L10n.keepAwakeModeTitle,
                    symbol: "power"
                ) {
                    Picker("", selection: $settings.mode) {
                        ForEach(KeepAwakeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel(L10n.keepAwakeModeTitle)
                }

                pickerRow(
                    title: L10n.keepAwakeDurationTitle,
                    symbol: "timer"
                ) {
                    Picker("", selection: $settings.duration) {
                        ForEach(KeepAwakeDuration.allCases) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel(L10n.keepAwakeDurationTitle)
                }

                activeSessionRow

                PreferenceInfoRow(
                    title: L10n.keepAwakeBatteryWarningTitle,
                    subtitle: L10n.keepAwakeBatteryWarning,
                    symbol: "battery.75percent",
                    theme: theme
                )

                PreferenceInfoRow(
                    title: L10n.keepAwakeRecordingOverlapTitle,
                    subtitle: L10n.keepAwakeRecordingOverlap,
                    symbol: "record.circle",
                    theme: theme
                )
            }

            if let errorMessage = service.state.errorMessage {
                PreferenceInfoRow(
                    title: L10n.keepAwakeStatusUnavailable,
                    subtitle: errorMessage,
                    symbol: "exclamationmark.triangle",
                    theme: theme
                )
            }
        }
    }

    @ViewBuilder
    private var activeSessionRow: some View {
        if service.isStartingOrActive {
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.preferencesAccent)
                    .frame(width: 30, height: 30)
                    .background(
                        palette.iconChipBackground,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.keepAwakeStatusTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(statusSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.keepAwakeStop, role: .destructive) {
                    Task { await service.stop() }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
        } else {
            PreferenceInfoRow(
                title: L10n.keepAwakeStatusTitle,
                subtitle: L10n.keepAwakeStatusIdle,
                symbol: "moon.zzz",
                theme: theme
            )
        }
    }

    private var statusSubtitle: String {
        guard let session = service.activeSession else {
            return L10n.keepAwakeStatusStarting
        }

        let detail: String
        if session.duration == .indefinite {
            detail = L10n.keepAwakeDurationIndefinite
        } else if let remainingMinutes = service.remainingMinutes {
            detail = String(format: L10n.keepAwakeRemainingMinutes, remainingMinutes)
        } else {
            detail = session.duration.displayName
        }
        return L10n.cmdKeepAwakeActiveSubtitle(mode: session.mode.displayName, detail: detail)
    }

    @ViewBuilder
    private func pickerRow<PickerContent: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> PickerContent
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(
                    palette.iconChipBackground,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Spacer()
            content()
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
