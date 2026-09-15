import SwiftUI

struct HealthBreakOverlayView: View {
    let state: HealthReminderState
    let settings: HealthReminderSettings
    let theme: AppTheme
    let onStartBreak: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private var progressText: String {
        "\(min(state.completedBreaksToday, settings.dailyGoal))/\(settings.dailyGoal)"
    }

    private var timeText: String {
        let minutes = state.remainingSeconds / 60
        let seconds = state.remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.preferencesAccent)
                    .frame(width: 34, height: 34)
                    .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.phase == .breakReady ? L10n.healthBreakReadyTitle : L10n.healthBreakingTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(String(format: L10n.healthTodayProgress, progressText))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if state.phase == .breaking {
                Text(timeText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(state.activityPaused ? L10n.healthActivityPausedMessage : L10n.healthBreakingMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(state.activityPaused ? .orange : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                Text(L10n.healthBreakReadyMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if state.phase == .breakReady {
                    Button(L10n.healthStartBreak) {
                        onStartBreak()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.preferencesAccent)
                } else {
                    Button(L10n.healthDoneBreak) {
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.preferencesAccent)
                }

                Button(L10n.healthSkipBreak) {
                    onSkip()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 22, y: 10)
    }
}
