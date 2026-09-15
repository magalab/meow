import SwiftUI

struct SystemMonitorPreferencesView: View {
    let theme: AppTheme
    @Binding var settings: SystemMonitorSettings
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsSystemMonitorEnabledTitle,
                subtitle: L10n.prefsSystemMonitorEnabledSubtitle,
                symbol: "gauge.with.dots.needle.67percent",
                theme: theme,
                isOn: $settings.enabled
            )

            VStack(alignment: .leading, spacing: 10) {
                settingPicker(
                    title: L10n.prefsSystemMonitorStatusStyle,
                    selection: $settings.statusStyle,
                    options: SystemMonitorStatusStyle.allCases,
                    titleFor: statusStyleTitle
                )
                settingPicker(
                    title: L10n.prefsSystemMonitorInterval,
                    selection: $settings.updateInterval,
                    options: [1.0, 2.0, 5.0, 10.0],
                    titleFor: { String(format: "%.0f s", $0) }
                )
                settingPicker(
                    title: L10n.prefsSystemMonitorHistory,
                    selection: $settings.historyDuration,
                    options: SystemMonitorHistoryDuration.allCases,
                    titleFor: historyTitle
                )
            }
            .padding(12)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.prefsSystemMonitorModules)
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(SystemMonitorModule.allCases, id: \.self) { module in
                        HStack(spacing: 8) {
                            Text(moduleTitle(module))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Toggle("", isOn: moduleBinding(module))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
        }
    }

    private func settingPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        titleFor: @escaping (Value) -> String
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(titleFor(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }

    private func moduleBinding(_ module: SystemMonitorModule) -> Binding<Bool> {
        Binding(
            get: { settings.enabledModules.contains(module) },
            set: { enabled in
                if enabled {
                    settings.enabledModules.insert(module)
                } else if settings.enabledModules.count > 1 {
                    settings.enabledModules.remove(module)
                }
            }
        )
    }

    private func statusStyleTitle(_ style: SystemMonitorStatusStyle) -> String {
        switch style {
        case .icon: return L10n.prefsSystemMonitorStatusIcon
        case .cpu: return L10n.prefsSystemMonitorStatusCPU
        case .memory: return L10n.prefsSystemMonitorStatusMemory
        case .cpuAndMemory: return L10n.prefsSystemMonitorStatusCPUAndMemory
        }
    }

    private func historyTitle(_ duration: SystemMonitorHistoryDuration) -> String {
        switch duration {
        case .fiveMinutes: return L10n.prefsSystemMonitorHistoryFiveMinutes
        case .tenMinutes: return L10n.prefsSystemMonitorHistoryTenMinutes
        }
    }

    private func moduleTitle(_ module: SystemMonitorModule) -> String {
        switch module {
        case .cpu: return L10n.prefsSystemMonitorCPU
        case .memory: return L10n.prefsSystemMonitorMemory
        case .gpu: return L10n.prefsSystemMonitorGPU
        case .network: return L10n.prefsSystemMonitorNetwork
        case .disk: return L10n.prefsSystemMonitorDisk
        case .power: return L10n.prefsSystemMonitorPower
        case .thermal: return L10n.prefsSystemMonitorThermal
        }
    }
}
