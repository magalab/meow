import SwiftUI

struct ThemePalette {
    let launcherAccent: Color
    let preferencesAccent: Color
    let danger: Color
    let launcherGradient: [Color]
    let preferencesGradient: [Color]
    let surfaceBackground: Color
    let surfaceStroke: Color
    let iconChipBackground: Color
    let filterCapsuleBackground: Color
    let selectionBackground: Color
    let selectionStroke: Color
    let preferencesPanelBackground: Color
    let preferencesPanelStroke: Color
}

enum MeowTheme {
    static func palette(theme: AppTheme, scheme: ColorScheme) -> ThemePalette {
        switch theme {
        case .gingerCat:
            return gingerCatPalette(for: scheme)
        case .mistBlue:
            return mistBluePalette(for: scheme)
        case .graphiteAmber:
            return graphiteAmberPalette(for: scheme)
        case .mossInk:
            return mossInkPalette(for: scheme)
        }
    }

    private static func gingerCatPalette(for scheme: ColorScheme) -> ThemePalette {
        ThemePalette(
            launcherAccent: Color(red: 0.85, green: 0.47, blue: 0.24),
            preferencesAccent: Color(red: 0.79, green: 0.37, blue: 0.29),
            danger: Color(red: 0.79, green: 0.29, blue: 0.27),
            launcherGradient: scheme == .dark
                ? [Color(red: 0.17, green: 0.11, blue: 0.09), Color(red: 0.11, green: 0.08, blue: 0.07)]
                : [Color(red: 1.0, green: 0.96, blue: 0.93), Color(red: 0.97, green: 0.91, blue: 0.85)],
            preferencesGradient: scheme == .dark
                ? [Color(red: 0.19, green: 0.13, blue: 0.11), Color(red: 0.13, green: 0.09, blue: 0.08)]
                : [Color(red: 1.0, green: 0.97, blue: 0.95), Color(red: 0.95, green: 0.9, blue: 0.85)],
            surfaceBackground: scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.76),
            surfaceStroke: scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.82),
            iconChipBackground: scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.9),
            filterCapsuleBackground: scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.78),
            selectionBackground: scheme == .dark ? Color(red: 0.85, green: 0.47, blue: 0.24).opacity(0.34) : Color(red: 0.85, green: 0.47, blue: 0.24).opacity(0.18),
            selectionStroke: scheme == .dark ? Color(red: 0.85, green: 0.47, blue: 0.24).opacity(0.64) : Color(red: 0.85, green: 0.47, blue: 0.24).opacity(0.42),
            preferencesPanelBackground: scheme == .dark ? Color(red: 0.79, green: 0.37, blue: 0.29).opacity(0.2) : Color(red: 0.79, green: 0.37, blue: 0.29).opacity(0.1),
            preferencesPanelStroke: scheme == .dark ? Color(red: 0.79, green: 0.37, blue: 0.29).opacity(0.44) : Color(red: 0.79, green: 0.37, blue: 0.29).opacity(0.26)
        )
    }

    private static func mistBluePalette(for scheme: ColorScheme) -> ThemePalette {
        ThemePalette(
            launcherAccent: Color(red: 0.23, green: 0.31, blue: 0.54),
            preferencesAccent: Color(red: 0.18, green: 0.54, blue: 0.48),
            danger: Color(red: 0.86, green: 0.21, blue: 0.2),
            launcherGradient: scheme == .dark
                ? [Color(red: 0.12, green: 0.14, blue: 0.19), Color(red: 0.08, green: 0.1, blue: 0.14)]
                : [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.92, green: 0.94, blue: 0.97)],
            preferencesGradient: scheme == .dark
                ? [Color(red: 0.13, green: 0.15, blue: 0.2), Color(red: 0.09, green: 0.11, blue: 0.16)]
                : [Color(red: 0.97, green: 0.98, blue: 0.99), Color(red: 0.93, green: 0.95, blue: 0.98)],
            surfaceBackground: scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.72),
            surfaceStroke: scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.8),
            iconChipBackground: scheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.9),
            filterCapsuleBackground: scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.75),
            selectionBackground: scheme == .dark ? Color(red: 0.23, green: 0.31, blue: 0.54).opacity(0.34) : Color(red: 0.23, green: 0.31, blue: 0.54).opacity(0.2),
            selectionStroke: scheme == .dark ? Color(red: 0.23, green: 0.31, blue: 0.54).opacity(0.64) : Color(red: 0.23, green: 0.31, blue: 0.54).opacity(0.46),
            preferencesPanelBackground: scheme == .dark ? Color(red: 0.18, green: 0.54, blue: 0.48).opacity(0.2) : Color(red: 0.18, green: 0.54, blue: 0.48).opacity(0.12),
            preferencesPanelStroke: scheme == .dark ? Color(red: 0.18, green: 0.54, blue: 0.48).opacity(0.44) : Color(red: 0.18, green: 0.54, blue: 0.48).opacity(0.3)
        )
    }

    private static func graphiteAmberPalette(for scheme: ColorScheme) -> ThemePalette {
        ThemePalette(
            launcherAccent: Color(red: 0.77, green: 0.54, blue: 0.23),
            preferencesAccent: Color(red: 0.48, green: 0.55, blue: 0.65),
            danger: Color(red: 0.84, green: 0.35, blue: 0.29),
            launcherGradient: scheme == .dark
                ? [Color(red: 0.14, green: 0.14, blue: 0.14), Color(red: 0.09, green: 0.09, blue: 0.09)]
                : [Color(red: 0.97, green: 0.96, blue: 0.95), Color(red: 0.92, green: 0.91, blue: 0.88)],
            preferencesGradient: scheme == .dark
                ? [Color(red: 0.15, green: 0.16, blue: 0.19), Color(red: 0.1, green: 0.11, blue: 0.13)]
                : [Color(red: 0.97, green: 0.97, blue: 0.96), Color(red: 0.92, green: 0.92, blue: 0.92)],
            surfaceBackground: scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.68),
            surfaceStroke: scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.76),
            iconChipBackground: scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.88),
            filterCapsuleBackground: scheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.73),
            selectionBackground: scheme == .dark ? Color(red: 0.77, green: 0.54, blue: 0.23).opacity(0.28) : Color(red: 0.77, green: 0.54, blue: 0.23).opacity(0.16),
            selectionStroke: scheme == .dark ? Color(red: 0.77, green: 0.54, blue: 0.23).opacity(0.56) : Color(red: 0.77, green: 0.54, blue: 0.23).opacity(0.36),
            preferencesPanelBackground: scheme == .dark ? Color(red: 0.48, green: 0.55, blue: 0.65).opacity(0.16) : Color(red: 0.48, green: 0.55, blue: 0.65).opacity(0.1),
            preferencesPanelStroke: scheme == .dark ? Color(red: 0.48, green: 0.55, blue: 0.65).opacity(0.34) : Color(red: 0.48, green: 0.55, blue: 0.65).opacity(0.24)
        )
    }

    private static func mossInkPalette(for scheme: ColorScheme) -> ThemePalette {
        ThemePalette(
            launcherAccent: Color(red: 0.29, green: 0.42, blue: 0.34),
            preferencesAccent: Color(red: 0.48, green: 0.36, blue: 0.24),
            danger: Color(red: 0.79, green: 0.33, blue: 0.3),
            launcherGradient: scheme == .dark
                ? [Color(red: 0.1, green: 0.13, blue: 0.11), Color(red: 0.07, green: 0.09, blue: 0.08)]
                : [Color(red: 0.96, green: 0.97, blue: 0.95), Color(red: 0.91, green: 0.93, blue: 0.9)],
            preferencesGradient: scheme == .dark
                ? [Color(red: 0.14, green: 0.12, blue: 0.1), Color(red: 0.09, green: 0.08, blue: 0.07)]
                : [Color(red: 0.97, green: 0.96, blue: 0.94), Color(red: 0.93, green: 0.9, blue: 0.85)],
            surfaceBackground: scheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.72),
            surfaceStroke: scheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.79),
            iconChipBackground: scheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.9),
            filterCapsuleBackground: scheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.75),
            selectionBackground: scheme == .dark ? Color(red: 0.29, green: 0.42, blue: 0.34).opacity(0.3) : Color(red: 0.29, green: 0.42, blue: 0.34).opacity(0.16),
            selectionStroke: scheme == .dark ? Color(red: 0.29, green: 0.42, blue: 0.34).opacity(0.58) : Color(red: 0.29, green: 0.42, blue: 0.34).opacity(0.34),
            preferencesPanelBackground: scheme == .dark ? Color(red: 0.48, green: 0.36, blue: 0.24).opacity(0.18) : Color(red: 0.48, green: 0.36, blue: 0.24).opacity(0.1),
            preferencesPanelStroke: scheme == .dark ? Color(red: 0.48, green: 0.36, blue: 0.24).opacity(0.36) : Color(red: 0.48, green: 0.36, blue: 0.24).opacity(0.24)
        )
    }
}
