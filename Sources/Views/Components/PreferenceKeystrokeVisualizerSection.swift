import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

private enum KeystrokePreferencePage: String, CaseIterable, Identifiable {
    case overview
    case display
    case position

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview: return L10n.prefsKeystrokePageOverview
        case .display: return L10n.prefsKeystrokePageDisplay
        case .position: return L10n.prefsKeystrokePagePosition
        }
    }
}

struct PreferenceKeystrokeVisualizerSection: View {
    let theme: AppTheme
    @ObservedObject var visualizerService: KeystrokeVisualizerService
    @Binding var enabled: Bool
    @Binding var showModifierOnly: Bool
    @Binding var style: KeystrokeOverlayStyle
    @Binding var overlayPosition: KeystrokeOverlayPosition
    @Binding var displayDuration: KeystrokeDisplayDuration
    @Binding var customDisplayDuration: Double
    @Binding var opacity: Double
    @Binding var historyCount: KeystrokeHistoryCount
    @Binding var displayMode: KeystrokeDisplayMode
    @Binding var overlayPoint: KeystrokeOverlayPoint?

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage = KeystrokePreferencePage.overview

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    private var hasPermission: Bool {
        visualizerService.permissionState == .trusted || AXIsProcessTrusted()
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsKeystrokeEnabledTitle,
                subtitle: L10n.prefsKeystrokeEnabledSubtitle,
                symbol: "keyboard",
                theme: theme,
                isOn: $enabled
            )

            if enabled {
                Picker("", selection: $selectedPage) {
                    ForEach(KeystrokePreferencePage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedPage {
                case .overview:
                    overviewPage
                case .display:
                    displayPage
                case .position:
                    positionPage
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: enabled)
        .animation(.snappy(duration: 0.22), value: selectedPage)
        .onAppear {
            refreshPermission()
        }
        .onChange(of: enabled) { _, _ in
            refreshPermission()
        }
    }

    private var overviewPage: some View {
        VStack(spacing: 10) {
            if !hasPermission {
                permissionRow
            }

            PreferenceToggleRow(
                title: L10n.prefsKeystrokeModifierTitle,
                subtitle: L10n.prefsKeystrokeModifierSubtitle,
                symbol: "command",
                theme: theme,
                isOn: $showModifierOnly
            )

            displayModeRow
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var displayPage: some View {
        VStack(spacing: 10) {
            styleRow
            durationRow
            historyRow
            opacityRow
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var positionPage: some View {
        VStack(spacing: 10) {
            positionRow
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            rowIcon("hand.raised")
            rowText(title: L10n.prefsKeystrokePermissionTitle, subtitle: L10n.prefsKeystrokePermissionSubtitle)

            Button(L10n.prefsKeystrokePermissionOpen) {
                openPrivacySettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var styleRow: some View {
        HStack(spacing: 12) {
            rowIcon("rectangle.on.rectangle")
            rowText(title: L10n.prefsKeystrokeStyleTitle, subtitle: L10n.prefsKeystrokeStyleSubtitle)

            compactPicker(selection: $style, width: 92)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var displayModeRow: some View {
        HStack(spacing: 12) {
            rowIcon("switch.2")
            rowText(title: L10n.prefsKeystrokeDisplayModeTitle, subtitle: L10n.prefsKeystrokeDisplayModeSubtitle)

            compactPicker(selection: $displayMode, width: 132)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            rowIcon("timer")
            rowText(title: L10n.prefsKeystrokeDurationTitle, subtitle: L10n.prefsKeystrokeDurationSubtitle)

            HStack(spacing: 8) {
                compactPicker(selection: $displayDuration, width: 92)

                if displayDuration == .custom {
                    Stepper(value: $customDisplayDuration, in: 0.3...10.0, step: 0.1) {
                        Text(String(format: "%.1fs", customDisplayDuration))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .frame(width: 126)
                }
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var positionRow: some View {
        HStack(spacing: 12) {
            rowIcon("rectangle.and.hand.point.up.left")
            rowText(title: L10n.prefsKeystrokePositionTitle, subtitle: L10n.prefsKeystrokePositionSubtitle)

            HStack(spacing: 8) {
                compactPicker(selection: $overlayPosition, width: 96)

                Button {
                    overlayPosition = .bottomCenter
                    overlayPoint = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .modifier(PreferenceIconButtonLabelStyle())
                }
                .buttonStyle(.plain)
                .help(L10n.prefsKeystrokePositionReset)
                .disabled(overlayPosition == .bottomCenter && overlayPoint == nil)
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var opacityRow: some View {
        HStack(spacing: 12) {
            rowIcon("circle.lefthalf.filled")
            rowText(title: L10n.prefsKeystrokeOpacityTitle, subtitle: L10n.prefsKeystrokeOpacitySubtitle)

            HStack(spacing: 8) {
                Slider(value: $opacity, in: 0.35...1.0, step: 0.05)
                    .frame(width: 132)
                Text("\(Int((opacity * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var historyRow: some View {
        HStack(spacing: 12) {
            rowIcon("rectangle.stack")
            rowText(title: L10n.prefsKeystrokeHistoryCountTitle, subtitle: L10n.prefsKeystrokeHistoryCountSubtitle)

            compactPicker(selection: $historyCount, width: 68)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private func compactPicker<Option>(
        selection: Binding<Option>,
        width: CGFloat
    ) -> some View where Option: CaseIterable & Hashable & Identifiable & KeystrokeDisplayNameProviding,
        Option.AllCases: RandomAccessCollection
    {
        Picker("", selection: selection) {
            ForEach(Option.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: width)
    }

    private func refreshPermission() {
        visualizerService.refreshPermissionState(prompt: false)
    }

    private func openPrivacySettings() {
        refreshPermission()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
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
