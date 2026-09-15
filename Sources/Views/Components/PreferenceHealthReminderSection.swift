import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

struct PreferenceHealthReminderSection: View {
    let theme: AppTheme
    @ObservedObject var service: HealthReminderService
    @Binding var settings: HealthReminderSettings

    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsHealthEnabledTitle,
                subtitle: L10n.prefsHealthEnabledSubtitle,
                symbol: "figure.mind.and.body",
                theme: theme,
                isOn: Binding(
                    get: { settings.enabled },
                    set: { settings.enabled = $0 }
                )
            )

            statusRow
            durationRow
            goalRow
            modeRow

            PreferenceToggleRow(
                title: L10n.prefsHealthActivityTitle,
                subtitle: L10n.prefsHealthActivitySubtitle,
                symbol: "cursorarrow.motionlines",
                theme: theme,
                isOn: Binding(
                    get: { settings.activityDetectionEnabled },
                    set: { settings.activityDetectionEnabled = $0 }
                )
            )

            PreferenceToggleRow(
                title: L10n.prefsHealthSoundTitle,
                subtitle: L10n.prefsHealthSoundSubtitle,
                symbol: "speaker.wave.2",
                theme: theme,
                isOn: Binding(
                    get: { settings.soundEnabled },
                    set: { settings.soundEnabled = $0 }
                )
            )
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            rowIcon("chart.line.uptrend.xyaxis")
            rowText(title: L10n.prefsHealthTodayTitle, subtitle: service.statusText())

            Text("\(min(service.state.completedBreaksToday, settings.dailyGoal))/\(settings.dailyGoal)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 54, alignment: .trailing)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            rowIcon("timer")
            rowText(title: L10n.prefsHealthDurationTitle, subtitle: L10n.prefsHealthDurationSubtitle)

            VStack(alignment: .trailing, spacing: 6) {
                Stepper(value: Binding(
                    get: { settings.workMinutes },
                    set: { settings.workMinutes = $0 }
                ), in: 5...180, step: 5) {
                    Text(String(format: L10n.healthWorkMinutesValue, settings.workMinutes))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Stepper(value: Binding(
                    get: { settings.breakSeconds },
                    set: { settings.breakSeconds = $0 }
                ), in: 10...1800, step: 10) {
                    Text(String(format: L10n.healthBreakSecondsValue, settings.breakSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 160)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var goalRow: some View {
        HStack(spacing: 12) {
            rowIcon("target")
            rowText(title: L10n.prefsHealthGoalTitle, subtitle: L10n.prefsHealthGoalSubtitle)

            Stepper(value: Binding(
                get: { settings.dailyGoal },
                set: { settings.dailyGoal = $0 }
            ), in: 1...24, step: 1) {
                Text(String(format: L10n.healthGoalValue, settings.dailyGoal))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 76, alignment: .trailing)
            }
            .frame(width: 132)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var modeRow: some View {
        HStack(spacing: 12) {
            rowIcon("rectangle.inset.filled")
            rowText(title: L10n.prefsHealthModeTitle, subtitle: L10n.prefsHealthModeSubtitle)

            Picker("", selection: Binding(
                get: { settings.breakMode },
                set: { settings.breakMode = $0 }
            )) {
                ForEach(HealthBreakMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 116)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.preferencesAccent)
            .frame(width: 30, height: 30)
            .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func rowText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
