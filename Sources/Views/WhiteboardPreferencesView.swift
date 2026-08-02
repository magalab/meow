import SwiftUI
import WhiteboardFeature

struct WhiteboardPreferencesView: View {
    let theme: AppTheme
    let hotkeyRegistrationError: String?
    @Binding var settings: WhiteboardSettings
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.whiteboardEnabledTitle,
                subtitle: L10n.whiteboardEnabledSubtitle,
                symbol: "scribble.variable",
                theme: theme,
                isOn: $settings.enabled
            )

            if settings.enabled {
                PreferenceHotkeyRecorderRow(
                    title: L10n.whiteboardHotkeyTitle,
                    subtitle: L10n.whiteboardHotkeySubtitle,
                    symbol: "keyboard",
                    theme: theme,
                    keyCode: settings.hotkeyKeyCode,
                    modifiers: settings.hotkeyModifiers
                ) { keyCode, modifiers in
                    settings.hotkeyKeyCode = keyCode
                    settings.hotkeyModifiers = modifiers
                }

                if let hotkeyRegistrationError {
                    Label(hotkeyRegistrationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                }

                pickerRow(
                    title: L10n.whiteboardIdleTitle,
                    subtitle: L10n.whiteboardIdleSubtitle,
                    symbol: "eye",
                    selection: $settings.idleVisibility,
                    options: [WhiteboardIdleVisibility.hidden, .visible]
                ) { value in
                    value == .hidden ? L10n.whiteboardIdleHidden : L10n.whiteboardIdleVisible
                }

                pickerRow(
                    title: L10n.whiteboardSurfaceTitle,
                    subtitle: L10n.whiteboardSurfaceSubtitle,
                    symbol: "rectangle.fill",
                    selection: $settings.surfaceStyle,
                    options: WhiteboardSurfaceStyle.allCases
                ) { value in
                    switch value {
                    case .transparent: return L10n.whiteboardSurfaceTransparent
                    case .paper: return L10n.whiteboardSurfacePaper
                    }
                }

                pickerRow(
                    title: L10n.whiteboardGuideTitle,
                    subtitle: L10n.whiteboardGuideSubtitle,
                    symbol: "circle.grid.3x3",
                    selection: $settings.guideStyle,
                    options: WhiteboardGuideStyle.allCases
                ) { value in
                    switch value {
                    case .none: return L10n.whiteboardGuideNone
                    case .dots: return L10n.whiteboardGuideDots
                    case .grid: return L10n.whiteboardGuideGrid
                    }
                }

                pickerRow(
                    title: L10n.whiteboardOutputBackgroundTitle,
                    subtitle: L10n.whiteboardOutputBackgroundSubtitle,
                    symbol: "square.and.arrow.up",
                    selection: $settings.outputBackgroundStyle,
                    options: WhiteboardOutputBackgroundStyle.allCases
                ) { value in
                    switch value {
                    case .transparent: return L10n.whiteboardOutputBackgroundTransparent
                    case .paper: return L10n.whiteboardOutputBackgroundPaper
                    }
                }

                PreferenceToggleRow(
                    title: L10n.whiteboardCaptureTitle,
                    subtitle: L10n.whiteboardCaptureSubtitle,
                    symbol: "camera.viewfinder",
                    theme: theme,
                    isOn: $settings.includeInCaptures
                )

                opacityRow

                PreferenceInfoRow(
                    title: L10n.whiteboardScopeTitle,
                    subtitle: L10n.whiteboardScopeSubtitle,
                    symbol: "display",
                    theme: theme
                )
            }
        }
        .animation(.snappy(duration: 0.22), value: settings.enabled)
    }

    private var opacityRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.whiteboardOpacityTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.whiteboardOpacitySubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Slider(value: $settings.editOpacity, in: 0.2...1, step: 0.05)
                .frame(width: 170)
            Text("\(Int(settings.editOpacity * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
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
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
