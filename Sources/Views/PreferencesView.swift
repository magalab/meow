import AppKit
import SwiftUI

struct PreferencesView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case general
        case appearance
        case about

        var id: String {
            rawValue
        }

        var localizedTitle: String {
            switch self {
            case .general: return L10n.prefsSectionGeneral
            case .appearance: return L10n.prefsSectionAppearance
            case .about: return L10n.prefsSectionAbout
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintpalette"
            case .about: return "info.circle"
            }
        }
    }

    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: Section = .general

    private var palette: ThemePalette {
        MeowTheme.palette(theme: viewModel.settings.theme, scheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette.preferencesGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(Section.allCases) { section in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                selectedSection = section
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selectedSection == section ? palette.preferencesAccent : Color.secondary)
                                Text(section.localizedTitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(selectedSection == section ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedSection == section
                                    ? palette.preferencesPanelBackground
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(selectedSection == section ? palette.preferencesPanelStroke : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.42))

                Divider()

                ScrollView {
                    VStack(spacing: 10) {
                        if selectedSection == .general {
                            PreferenceToggleRow(
                                title: L10n.prefsAutoLaunchTitle,
                                subtitle: L10n.prefsAutoLaunchSubtitle,
                                symbol: "power.circle",
                                theme: viewModel.settings.theme,
                                isOn: animatedBinding(
                                    get: { viewModel.settings.autoLaunch },
                                    set: { viewModel.settings.autoLaunch = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                            PreferenceToggleRow(
                                title: L10n.prefsClipboardTitle,
                                subtitle: L10n.prefsClipboardSubtitle,
                                symbol: "clipboard",
                                theme: viewModel.settings.theme,
                                isOn: animatedBinding(
                                    get: { viewModel.settings.clipboardHistoryEnabled },
                                    set: { viewModel.settings.clipboardHistoryEnabled = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                            PreferenceHotkeyRecorderRow(
                                title: L10n.prefsHotkeyTitle,
                                subtitle: L10n.prefsHotkeySubtitle,
                                symbol: "keyboard",
                                theme: viewModel.settings.theme,
                                keyCode: viewModel.settings.hotkeyKeyCode,
                                modifiers: viewModel.settings.hotkeyModifiers
                            ) { keyCode, modifiers in
                                viewModel.settings.hotkeyKeyCode = keyCode
                                viewModel.settings.hotkeyModifiers = modifiers
                            }
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))

                            PreferenceLanguageRow(
                                theme: viewModel.settings.theme,
                                language: Binding(
                                    get: { viewModel.settings.language },
                                    set: { viewModel.settings.language = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                        }

                        if selectedSection == .appearance {
                            PreferenceThemeRow(
                                theme: Binding(
                                    get: { viewModel.settings.theme },
                                    set: { viewModel.settings.theme = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                            PreferenceToggleRow(
                                title: L10n.prefsDockTitle,
                                subtitle: L10n.prefsDockSubtitle,
                                symbol: "dock.rectangle",
                                theme: viewModel.settings.theme,
                                isOn: animatedBinding(
                                    get: { viewModel.settings.showDockIcon },
                                    set: { viewModel.settings.showDockIcon = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                            PreferenceToggleRow(
                                title: L10n.prefsMenuBarTitle,
                                subtitle: L10n.prefsMenuBarSubtitle,
                                symbol: "menubar.rectangle",
                                theme: viewModel.settings.theme,
                                isOn: animatedBinding(
                                    get: { viewModel.settings.showStatusItem },
                                    set: { viewModel.settings.showStatusItem = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if selectedSection == .about {
                            PreferenceAboutSectionView(theme: viewModel.settings.theme)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .padding(16)
                    .animation(.snappy(duration: 0.28), value: selectedSection)
                }
                .background(Color.white.opacity(colorScheme == .dark ? 0.01 : 0.16))
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.76 : 0.84))
        }
        .frame(width: 620, height: 448)
        .id(lang.refreshToken)
    }

    private func animatedBinding(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(
            get: get,
            set: { newValue in
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.08)) {
                    set(newValue)
                }
            }
        )
    }
}

private struct PreferenceAboutSectionView: View {
    let theme: AppTheme

    @Environment(\.colorScheme) private var colorScheme

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(palette.preferencesAccent)
                    .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Meow")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("v\(version) (\(build))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            aboutRow(title: L10n.prefsAboutVersion, value: version)
            aboutRow(title: L10n.prefsAboutBuild, value: build)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.prefsAboutPrivacy)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(L10n.prefsAboutPrivacySubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            HStack {
                Text(L10n.prefsAboutRepo)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button(L10n.prefsAboutOpenRepo) {
                    if let url = URL(string: "https://github.com/magalab/meow") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(palette.preferencesPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.preferencesPanelStroke, lineWidth: 1)
        )
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
