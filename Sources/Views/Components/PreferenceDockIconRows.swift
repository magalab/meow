import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

struct PreferenceDockIconPreview: View {
    let theme: AppTheme
    let style: DockIconStyle
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private var previewImage: NSImage {
        switch style {
        case .default: return NSApp.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage()
        case .calendar: return DockIconService.renderCalendarIcon(size: 80)
        case .flat: return DockIconService.renderFlatIcon(size: 80)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.prefsDockTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(style.displayName)
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
        .id(lang.refreshToken)
    }
}

struct PreferenceDockIconStyleRow: View {
    let theme: AppTheme
    @Binding var style: DockIconStyle
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.dashed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsDockIconTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsDockIconSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $style) {
                ForEach(DockIconStyle.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
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
