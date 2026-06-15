import SwiftUI

private enum SpeechPreferencePage: String, CaseIterable, Identifiable {
    case recognition
    case synthesis
    case models
    case history

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recognition: return L10n.speechPageRecognition
        case .synthesis: return L10n.speechPageSynthesis
        case .models: return L10n.speechPageModels
        case .history: return L10n.speechPageHistory
        }
    }
}

struct PreferenceSpeechSection: View {
    private enum Confirmation: Int, Identifiable {
        case downloadModel
        case clearHistory

        var id: Int { rawValue }
    }

    let theme: AppTheme
    @Binding var settings: SpeechSettings
    @ObservedObject var modelStore: SpeechModelStore
    @ObservedObject var historyStore: SpeechHistoryStore
    @ObservedObject var recognitionService: SpeechRecognitionService
    @Binding var ttsSettings: TtsSettings
    @ObservedObject var ttsModelStore: TtsModelStore
    @ObservedObject var synthesisService: SpeechSynthesisService

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage = SpeechPreferencePage.recognition
    @State private var confirmation: Confirmation?
    @State private var isHistoryExpanded = false
    @State private var copiedEntryID: SpeechHistoryEntry.ID?
    @State private var copyResetTask: Task<Void, Never>?

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.speechEnabledTitle,
                subtitle: L10n.speechEnabledSubtitle,
                symbol: "waveform",
                theme: theme,
                isOn: $settings.enabled
            )

            PreferenceToggleRow(
                title: L10n.ttsEnabledTitle,
                subtitle: L10n.ttsEnabledSubtitle,
                symbol: "waveform.badge.plus",
                theme: theme,
                isOn: $ttsSettings.enabled
            )

            if settings.enabled || ttsSettings.enabled {
                Picker("", selection: $selectedPage) {
                    ForEach(SpeechPreferencePage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedPage {
                case .recognition:
                    recognitionPage
                case .synthesis:
                    synthesisPage
                case .models:
                    modelsPage
                case .history:
                    historyPage
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: settings.enabled)
        .animation(.snappy(duration: 0.22), value: ttsSettings.enabled)
        .animation(.snappy(duration: 0.22), value: selectedPage)
        .alert(item: $confirmation) { confirmation in
            switch confirmation {
            case .downloadModel:
                return Alert(
                    title: Text(settings.model.downloadConfirmTitle),
                    message: Text(settings.model.downloadConfirmMessage),
                    primaryButton: .cancel(Text(L10n.actionCancel)),
                    secondaryButton: .default(Text(L10n.speechModelDownload)) {
                        modelStore.downloadModel()
                    }
                )
            case .clearHistory:
                return Alert(
                    title: Text(L10n.speechHistoryClearTitle),
                    message: Text(L10n.speechHistoryClearMessage),
                    primaryButton: .cancel(Text(L10n.actionCancel)),
                    secondaryButton: .destructive(Text(L10n.speechHistoryClear)) {
                        historyStore.clear()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var recognitionPage: some View {
        if settings.enabled {
            VStack(spacing: 10) {
                permissionRow

                PreferenceToggleRow(
                    title: L10n.speechSoundTitle,
                    subtitle: L10n.speechSoundSubtitle,
                    symbol: "speaker.wave.2",
                    theme: theme,
                    isOn: $settings.soundEnabled
                )

                PreferenceHotkeyRecorderRow(
                    title: L10n.speechHotkeyTitle,
                    subtitle: L10n.speechHotkeySubtitle,
                    symbol: "mic",
                    theme: theme,
                    keyCode: settings.hotkeyKeyCode,
                    modifiers: settings.hotkeyModifiers
                ) { keyCode, modifiers in
                    settings.hotkeyKeyCode = keyCode
                    settings.hotkeyModifiers = modifiers
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        } else {
            disabledPage(L10n.speechRecognitionDisabled)
        }
    }

    @ViewBuilder
    private var synthesisPage: some View {
        if ttsSettings.enabled {
            TtsPreferencesView(
                mode: .synthesis,
                theme: theme,
                settings: $ttsSettings,
                modelStore: ttsModelStore,
                synthesisService: synthesisService
            )
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        } else {
            disabledPage(L10n.ttsDisabled)
        }
    }

    private var modelsPage: some View {
        VStack(spacing: 10) {
            if settings.enabled {
                modelRow
            }
            if ttsSettings.enabled {
                TtsPreferencesView(
                    mode: .model,
                    theme: theme,
                    settings: $ttsSettings,
                    modelStore: ttsModelStore,
                    synthesisService: synthesisService
                )
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }

    @ViewBuilder
    private var historyPage: some View {
        if settings.enabled {
            VStack(spacing: 10) {
                retentionRow
                historySection
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        } else {
            disabledPage(L10n.speechRecognitionDisabled)
        }
    }

    private func disabledPage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .speechPanel(palette)
    }

    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                speechIcon("externaldrive.badge.checkmark")
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.speechModelSelectionTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(settings.model.description)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Picker("", selection: $settings.model) {
                        ForEach(SpeechModelKind.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 210)

                    modelActions
                }
            }

            if case let .downloading(progress) = modelStore.state {
                ProgressView(value: progress)
                    .tint(palette.preferencesAccent)
                Text(String(format: L10n.speechModelDownloading, progress * 100))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(modelSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .speechPanel(palette)
    }

    @ViewBuilder
    private var modelActions: some View {
        switch modelStore.state {
        case .notInstalled, .failed:
            Button(L10n.speechModelDownload) {
                confirmation = .downloadModel
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(palette.preferencesAccent)
        case .downloading:
            Button(L10n.actionCancel) {
                modelStore.cancelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .installed:
            HStack(spacing: 6) {
                Button(L10n.speechModelOpenFolder) {
                    modelStore.openModelFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(L10n.speechModelDelete, role: .destructive) {
                    recognitionService.unloadModel()
                    modelStore.deleteModel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(recognitionService.state.isActive)
            }
        }
    }

    private var modelSubtitle: String {
        switch modelStore.state {
        case .notInstalled:
            return L10n.speechModelNotInstalled
        case .downloading:
            return settings.model.description
        case .installed:
            return L10n.speechModelInstalled
        case let .failed(message):
            return message
        }
    }

    private var permissionRow: some View {
        HStack(spacing: 12) {
            speechIcon("mic.badge.plus")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.speechPermissionTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(permissionSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if recognitionService.permissionState != .granted {
                Button(permissionActionTitle) {
                    recognitionService.requestMicrophonePermission()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Label(L10n.speechPermissionGranted, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .speechPanel(palette)
    }

    private var permissionSubtitle: String {
        switch recognitionService.permissionState {
        case .granted:
            return L10n.speechPermissionGrantedSubtitle
        case .notDetermined:
            return L10n.speechPermissionNotDetermined
        case .denied:
            return L10n.speechPermissionDenied
        }
    }

    private var permissionActionTitle: String {
        switch recognitionService.permissionState {
        case .notDetermined:
            return L10n.speechPermissionRequest
        case .denied:
            return L10n.speechPermissionOpen
        case .granted:
            return ""
        }
    }

    private var retentionRow: some View {
        HStack(spacing: 12) {
            speechIcon("calendar.badge.clock")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.speechRetentionTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(L10n.speechRetentionSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $settings.retentionDays) {
                Text(L10n.speechRetention7Days).tag(7)
                Text(L10n.speechRetention30Days).tag(30)
                Text(L10n.speechRetention90Days).tag(90)
                Text(L10n.speechRetentionForever).tag(0)
            }
            .labelsHidden()
            .frame(width: 120)
        }
        .speechPanel(palette)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isHistoryExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isHistoryExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 12)
                        Text(L10n.speechHistoryTitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(.plain)

                if !historyStore.entries.isEmpty {
                    Text(historyCountSummary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Button(L10n.speechHistoryOpenFolder) {
                    historyStore.openFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(L10n.speechHistoryClear, role: .destructive) {
                    confirmation = .clearHistory
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(historyStore.entries.isEmpty)
            }

            if isHistoryExpanded {
                if historyStore.entries.isEmpty {
                    Text(L10n.speechHistoryEmpty)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ForEach(historyStore.entries.prefix(20)) { entry in
                        historyRow(entry)
                        if entry.id != historyStore.entries.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .speechPanel(palette)
    }

    private func historyRow(_ entry: SpeechHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                historyStore.play(entry)
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Text(historyMetadata(entry))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if copiedEntryID == entry.id {
                Button {
                    copyHistoryEntry(entry)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .help(L10n.speechHistoryCopied)
            } else {
                Button {
                    copyHistoryEntry(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(palette.preferencesAccent)
                .help(L10n.speechHistoryCopy)
            }

            Button(role: .destructive) {
                historyStore.delete(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.actionMenuDelete)
        }
    }

    private func copyHistoryEntry(_ entry: SpeechHistoryEntry) {
        historyStore.copyText(entry)
        copiedEntryID = entry.id
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            if copiedEntryID == entry.id {
                copiedEntryID = nil
            }
        }
    }

    private func historyMetadata(_ entry: SpeechHistoryEntry) -> String {
        let date = entry.createdAt.formatted(date: .abbreviated, time: .shortened)
        let duration = String(format: "%.1fs", entry.duration)
        if let language = entry.language, !language.isEmpty {
            return "\(date) · \(duration) · \(language)"
        }
        return "\(date) · \(duration)"
    }

    private var historyCountSummary: String {
        String(format: L10n.speechHistoryCount, historyStore.entries.count)
    }

    private func speechIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.preferencesAccent)
            .frame(width: 30, height: 30)
            .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private extension View {
    func speechPanel(_ palette: ThemePalette) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
    }
}
