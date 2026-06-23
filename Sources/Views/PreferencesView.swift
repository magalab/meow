import AppKit
import SwiftUI

enum PreferenceSection: String, CaseIterable, Identifiable {
    case general
    case screenshot
    case recording
    case history
    case authenticator
    case keyboard
    case speech
    case health
    case ai
    case fileHosting
    case about

    var id: String {
        rawValue
    }

    var localizedTitle: String {
        switch self {
        case .general: return L10n.prefsSectionGeneral
        case .screenshot: return L10n.prefsSectionScreenshot
        case .recording: return L10n.prefsSectionRecording
        case .history: return L10n.prefsSectionHistory
        case .authenticator: return L10n.prefsSectionAuthenticator
        case .keyboard: return L10n.prefsSectionKeyboard
        case .speech: return L10n.prefsSectionSpeech
        case .health: return L10n.prefsSectionHealth
        case .ai: return L10n.prefsSectionAI
        case .fileHosting: return L10n.prefsSectionFileHosting
        case .about: return L10n.prefsSectionAbout
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .screenshot: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .history: return "clock.arrow.circlepath"
        case .authenticator: return AuthenticatorVisuals.symbol
        case .keyboard: return "keyboard"
        case .speech: return "waveform"
        case .health: return "figure.mind.and.body"
        case .ai: return "sparkles"
        case .fileHosting: return "externaldrive.badge.icloud"
        case .about: return "info.circle"
        }
    }
}

private enum GeneralPreferencePage: String, CaseIterable, Identifiable {
    case basics
    case dock
    case appearance
    case shortcuts

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .basics: return L10n.prefsGeneralPageBasics
        case .dock: return L10n.prefsGeneralPageDock
        case .appearance: return L10n.prefsGeneralPageAppearance
        case .shortcuts: return L10n.prefsGeneralPageShortcuts
        }
    }
}

private enum HistoryPreferencePage: String, CaseIterable, Identifiable {
    case screenshots
    case recordings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshots: return L10n.prefsSectionScreenshot
        case .recordings: return L10n.prefsSectionRecording
        }
    }
}

@MainActor
final class PreferencesNavigationState: ObservableObject {
    @Published var selectedSection: PreferenceSection = .general
}

struct RecordingHistoryContext {
    let store: RecordingStore
    let onDelete: (RecordingArtifact) -> Void
    let onTrim: (RecordingArtifact) -> Void
}

struct PreferencesView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var navigation: PreferencesNavigationState
    @ObservedObject var aiChatHistoryStore: AIChatHistoryStore
    @ObservedObject var keystrokeVisualizerService: KeystrokeVisualizerService
    @ObservedObject var authenticatorService: AuthenticatorService
    @ObservedObject var healthReminderService: HealthReminderService
    #if MEOW_VOICE
    @ObservedObject var speechModelStore: SpeechModelStore
    @ObservedObject var speechHistoryStore: SpeechHistoryStore
    @ObservedObject var speechRecognitionService: SpeechRecognitionService
    @ObservedObject var ttsModelStore: TtsModelStore
    @ObservedObject var speechSynthesisService: SpeechSynthesisService
    #endif
    @ObservedObject var fileUploadService: FileUploadService
    let makeCaptureHistoryView: (AppTheme) -> CaptureHistoryView
    let recordingHistoryContext: RecordingHistoryContext
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedGeneralPage = GeneralPreferencePage.basics
    @State private var selectedHistoryPage = HistoryPreferencePage.screenshots

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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableSections) { section in
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    navigation.selectedSection = section
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: section.icon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(navigation.selectedSection == section ? palette.preferencesAccent : Color.secondary)
                                    Text(section.localizedTitle)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundStyle(navigation.selectedSection == section ? Color.primary : Color.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .background(
                                    navigation.selectedSection == section
                                        ? palette.preferencesPanelBackground
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(navigation.selectedSection == section ? palette.preferencesPanelStroke : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.42))

                Divider()

                ScrollView {
                    VStack(spacing: 10) {
                        if navigation.selectedSection == .general {
                            generalPreferencesSection
                        }

                        if navigation.selectedSection == .authenticator {
                            AuthenticatorPreferencesView(
                                theme: viewModel.settings.theme,
                                service: authenticatorService,
                                enabled: animatedBinding(for: \.authenticatorEnabled),
                                iCloudSyncEnabled: Binding(
                                    get: { viewModel.settings.authenticatorICloudSyncEnabled },
                                    set: { viewModel.settings.authenticatorICloudSyncEnabled = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if navigation.selectedSection == .screenshot {
                            ScreenshotPreferencesView(
                                theme: viewModel.settings.theme,
                                settings: Binding(
                                    get: { viewModel.settings.screenshot },
                                    set: { viewModel.settings.screenshot = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if navigation.selectedSection == .recording {
                            RecordingPreferencesView(
                                theme: viewModel.settings.theme,
                                settings: Binding(
                                    get: { viewModel.settings.recording },
                                    set: { viewModel.settings.recording = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if navigation.selectedSection == .history {
                            historyPreferencesSection
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        #if MEOW_VOICE
                        if navigation.selectedSection == .speech {
                            PreferenceSpeechSection(
                                theme: viewModel.settings.theme,
                                settings: Binding(
                                    get: { viewModel.settings.speech },
                                    set: { viewModel.settings.speech = $0 }
                                ),
                                modelStore: speechModelStore,
                                historyStore: speechHistoryStore,
                                recognitionService: speechRecognitionService,
                                ttsSettings: Binding(
                                    get: { viewModel.settings.tts },
                                    set: { viewModel.settings.tts = $0 }
                                ),
                                ttsModelStore: ttsModelStore,
                                synthesisService: speechSynthesisService
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }
                        #endif

                        if navigation.selectedSection == .health {
                            PreferenceHealthReminderSection(
                                theme: viewModel.settings.theme,
                                service: healthReminderService,
                                settings: Binding(
                                    get: { viewModel.settings.healthReminder },
                                    set: { viewModel.settings.healthReminder = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if navigation.selectedSection == .fileHosting {
                            FileHostingPreferencesView(
                                settings: Binding(
                                    get: { viewModel.settings.fileHosting },
                                    set: { viewModel.settings.fileHosting = $0 }
                                ),
                                service: fileUploadService,
                                theme: viewModel.settings.theme
                            )
                        }

                        if navigation.selectedSection == .keyboard {
                            PreferenceKeystrokeVisualizerSection(
                                theme: viewModel.settings.theme,
                                visualizerService: keystrokeVisualizerService,
                                enabled: animatedBinding(for: \.keystrokeVisualizerEnabled),
                                showModifierOnly: animatedBinding(for: \.keystrokeVisualizerShowModifierOnly),
                                style: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerStyle },
                                    set: { viewModel.settings.keystrokeVisualizerStyle = $0 }
                                ),
                                overlayPosition: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerOverlayPosition },
                                    set: { viewModel.settings.keystrokeVisualizerOverlayPosition = $0 }
                                ),
                                displayDuration: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerDisplayDuration },
                                    set: { viewModel.settings.keystrokeVisualizerDisplayDuration = $0 }
                                ),
                                customDisplayDuration: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerCustomDisplayDuration },
                                    set: { viewModel.settings.keystrokeVisualizerCustomDisplayDuration = $0 }
                                ),
                                opacity: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerOpacity },
                                    set: { viewModel.settings.keystrokeVisualizerOpacity = $0 }
                                ),
                                historyCount: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerHistoryCount },
                                    set: { viewModel.settings.keystrokeVisualizerHistoryCount = $0 }
                                ),
                                displayMode: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerDisplayMode },
                                    set: { viewModel.settings.keystrokeVisualizerDisplayMode = $0 }
                                ),
                                overlayPoint: Binding(
                                    get: { viewModel.settings.keystrokeVisualizerOverlayPoint },
                                    set: { viewModel.settings.keystrokeVisualizerOverlayPoint = $0 }
                                )
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if navigation.selectedSection == .ai {
                            PreferenceAISettingsSection(
                                theme: viewModel.settings.theme,
                                settings: Binding(
                                    get: { viewModel.settings.ai },
                                    set: { viewModel.settings.ai = $0 }
                                ),
                                historyStore: aiChatHistoryStore
                            )
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }

                        if navigation.selectedSection == .about {
                            PreferenceAboutSectionView(theme: viewModel.settings.theme)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .padding(16)
                    .animation(.snappy(duration: 0.28), value: navigation.selectedSection)
                }
                .background(Color.white.opacity(colorScheme == .dark ? 0.01 : 0.16))
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.76 : 0.84))
        }
        .frame(width: 760, height: 500)
        .id(lang.refreshToken)
    }

    private var availableSections: [PreferenceSection] {
        BuildEdition.includesVoiceFeatures
            ? PreferenceSection.allCases
            : PreferenceSection.allCases.filter { $0 != .speech }
    }

    private var generalPreferencesSection: some View {
        VStack(spacing: 10) {
            Picker("", selection: $selectedGeneralPage) {
                ForEach(GeneralPreferencePage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)

            switch selectedGeneralPage {
            case .basics:
                generalBasicsPage
            case .dock:
                generalDockPage
            case .appearance:
                generalAppearancePage
            case .shortcuts:
                generalShortcutsPage
            }
        }
        .animation(.snappy(duration: 0.22), value: selectedGeneralPage)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var generalBasicsPage: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsAutoLaunchTitle,
                subtitle: L10n.prefsAutoLaunchSubtitle,
                symbol: "power.circle",
                theme: viewModel.settings.theme,
                isOn: animatedBinding(for: \.autoLaunch)
            )

            PreferenceToggleRow(
                title: L10n.prefsClipboardTitle,
                subtitle: L10n.prefsClipboardSubtitle,
                symbol: "clipboard",
                theme: viewModel.settings.theme,
                isOn: animatedBinding(for: \.clipboardHistoryEnabled)
            )

            if viewModel.settings.clipboardHistoryEnabled {
                PreferenceToggleRow(
                    title: L10n.prefsClipboardImagePreviewTitle,
                    subtitle: L10n.prefsClipboardImagePreviewSubtitle,
                    symbol: "photo.on.rectangle",
                    theme: viewModel.settings.theme,
                    isOn: animatedBinding(for: \.clipboardShowImagePreviews)
                )
            }

            PreferenceLanguageRow(
                theme: viewModel.settings.theme,
                language: Binding(
                    get: { viewModel.settings.language },
                    set: { viewModel.settings.language = $0 }
                )
            )
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var generalDockPage: some View {
        VStack(spacing: 10) {
            PreferenceDockIconPreview(
                theme: viewModel.settings.theme,
                style: viewModel.settings.dockIconStyle
            )

            PreferenceDockIconStyleRow(
                theme: viewModel.settings.theme,
                style: Binding(
                    get: { viewModel.settings.dockIconStyle },
                    set: { viewModel.settings.dockIconStyle = $0 }
                )
            )

            PreferenceToggleRow(
                title: L10n.prefsDockTitle,
                subtitle: L10n.prefsDockSubtitle,
                symbol: "dock.rectangle",
                theme: viewModel.settings.theme,
                isOn: animatedBinding(for: \.showDockIcon)
            )

            PreferenceToggleRow(
                title: L10n.prefsMenuBarTitle,
                subtitle: L10n.prefsMenuBarSubtitle,
                symbol: "menubar.rectangle",
                theme: viewModel.settings.theme,
                isOn: animatedBinding(for: \.showStatusItem)
            )

            PreferenceDateIconRow(
                theme: viewModel.settings.theme,
                style: Binding(
                    get: { viewModel.settings.dateIconStyle },
                    set: { viewModel.settings.dateIconStyle = $0 }
                )
            )
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var generalAppearancePage: some View {
        VStack(spacing: 10) {
            PreferenceThemeRow(
                theme: Binding(
                    get: { viewModel.settings.theme },
                    set: { viewModel.settings.theme = $0 }
                )
            )
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var generalShortcutsPage: some View {
        VStack(spacing: 10) {
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

            PreferenceHotkeyRecorderRow(
                title: L10n.prefsTranslateHotkeyTitle,
                subtitle: L10n.prefsTranslateHotkeySubtitle,
                symbol: "translate",
                theme: viewModel.settings.theme,
                keyCode: viewModel.settings.translateHotkeyKeyCode,
                modifiers: viewModel.settings.translateHotkeyModifiers
            ) { keyCode, modifiers in
                viewModel.settings.translateHotkeyKeyCode = keyCode
                viewModel.settings.translateHotkeyModifiers = modifiers
            }

            PreferenceHotkeyRecorderRow(
                title: L10n.prefsTtsHotkeyTitle,
                subtitle: L10n.prefsTtsHotkeySubtitle,
                symbol: "speaker.wave.2",
                theme: viewModel.settings.theme,
                keyCode: viewModel.settings.ttsHotkeyKeyCode,
                modifiers: viewModel.settings.ttsHotkeyModifiers
            ) { keyCode, modifiers in
                viewModel.settings.ttsHotkeyKeyCode = keyCode
                viewModel.settings.ttsHotkeyModifiers = modifiers
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    private var historyPreferencesSection: some View {
        VStack(spacing: 10) {
            Picker("", selection: $selectedHistoryPage) {
                ForEach(HistoryPreferencePage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)

            switch selectedHistoryPage {
            case .screenshots:
                makeCaptureHistoryView(viewModel.settings.theme)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.preferencesPanelStroke, lineWidth: 1)
                    )
            case .recordings:
                RecordingHistoryView(
                    store: recordingHistoryContext.store,
                    theme: viewModel.settings.theme,
                    onDelete: recordingHistoryContext.onDelete,
                    onTrim: recordingHistoryContext.onTrim
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.preferencesPanelStroke, lineWidth: 1)
                )
            }
        }
        .animation(.snappy(duration: 0.22), value: selectedHistoryPage)
    }

    private func animatedBinding(for keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.settings[keyPath: keyPath]
            },
            set: { newValue in
                withAnimation(.snappy(duration: 0.22, extraBounce: 0.08)) {
                    viewModel.settings[keyPath: keyPath] = newValue
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
