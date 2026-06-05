import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }
}

struct PreferenceHotkeyRecorderRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let theme: AppTheme
    let keyCode: UInt32
    let modifiers: UInt32
    let onSave: (UInt32, UInt32) -> Void

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(isRecording ? L10n.prefsHotkeyRecordingHint : subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isRecording ? L10n.prefsHotkeyRecording : KeyDisplayFormatter.shortcutLabel(keyCode: keyCode, modifiers: modifiers)) {
                startRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isRecording ? .orange : palette.preferencesAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)

            if keyCode == 53 {
                // Esc cancels recording.
                isRecording = false
                stopRecording()
                return nil
            }

            if KeyDisplayFormatter.isModifierOnlyKey(keyCode) {
                return nil
            }

            let modifiers = carbonModifiers(from: event.modifierFlags)
            if modifiers == 0 {
                return nil
            }

            onSave(keyCode, modifiers)
            isRecording = false
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

}

struct PreferenceThemeRow: View {
    @Binding var theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintpalette")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsThemeTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsThemeSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(palette.launcherAccent)
                Circle()
                    .fill(palette.preferencesAccent)
            }
            .frame(width: 28, height: 12)

            Picker("", selection: $theme) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.displayName).tag(option)
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

struct PreferenceDateIconRow: View {
    let theme: AppTheme
    @Binding var style: DateIconStyle
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsDateIconTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsDateIconSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $style) {
                ForEach(DateIconStyle.allCases) { option in
                    Text(option.displayName).tag(option)
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

struct PreferenceLanguageRow: View {
    let theme: AppTheme
    @Binding var language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsLanguageTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(L10n.prefsLanguageSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
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

            if enabled && !hasPermission {
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
            styleRow
            positionRow
            durationRow
            historyRow
            opacityRow
        }
        .onAppear {
            refreshPermission()
        }
        .onChange(of: enabled) { _, _ in
            refreshPermission()
        }
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

struct PreferenceAISettingsSection: View {
    let theme: AppTheme
    @Binding var settings: AISettings
    @ObservedObject var historyStore: AIChatHistoryStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealsAPIKey = false
    @State private var isLoadingModels = false
    @State private var modelOptions: [String] = []
    @State private var modelLoadError: String?
    @State private var showsModelPicker = false
    @State private var showsClearHistoryConfirmation = false

    private let aiService = AIChatService()

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            fieldRow(
                title: L10n.prefsAIEndpointTitle,
                subtitle: L10n.prefsAIEndpointSubtitle,
                symbol: "network",
                text: $settings.endpoint
            )
            apiKeyRow
            modelRow
            historyRow
        }
        .alert(L10n.prefsAIHistoryClearTitle, isPresented: $showsClearHistoryConfirmation) {
            Button(L10n.actionCancel, role: .cancel) {}
            Button(L10n.prefsAIHistoryClear, role: .destructive) {
                historyStore.clearAll()
            }
        } message: {
            Text(L10n.prefsAIHistoryClearMessage)
        }
    }

    private func fieldRow(
        title: String,
        subtitle: String,
        symbol: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(symbol)
            rowText(title: title, subtitle: subtitle)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 260)
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var apiKeyRow: some View {
        HStack(spacing: 12) {
            rowIcon("key")
            rowText(title: L10n.prefsAIKeyTitle, subtitle: L10n.prefsAIKeySubtitle)

            HStack(spacing: 6) {
                Group {
                    if revealsAPIKey {
                        TextField("", text: $settings.apiKey)
                    } else {
                        SecureField("", text: $settings.apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 216)

                Button {
                    copy(settings.apiKey)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .modifier(PreferenceIconButtonLabelStyle())
                }
                .buttonStyle(.plain)
                .help(L10n.prefsAIKeyCopy)
                .disabled(settings.apiKey.isEmpty)

                Button {
                    revealsAPIKey.toggle()
                } label: {
                    Image(systemName: revealsAPIKey ? "eye.slash" : "eye")
                        .modifier(PreferenceIconButtonLabelStyle())
                }
                .buttonStyle(.plain)
                .help(revealsAPIKey ? L10n.prefsAIKeyHide : L10n.prefsAIKeyReveal)
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                rowIcon("cpu")
                rowText(title: L10n.prefsAIModelTitle, subtitle: L10n.prefsAIModelSubtitle)

                HStack(spacing: 6) {
                    TextField("", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 190)

                    Button {
                        showsModelPicker.toggle()
                    } label: {
                        Image(systemName: "chevron.down")
                            .modifier(PreferenceIconButtonLabelStyle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.prefsAIModelChoose)
                    .disabled(modelOptions.isEmpty)
                    .popover(isPresented: $showsModelPicker, arrowEdge: .bottom) {
                        modelPicker
                            .padding(8)
                    }

                    Button {
                        refreshModels()
                    } label: {
                        if isLoadingModels {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                                )
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .modifier(PreferenceIconButtonLabelStyle())
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L10n.prefsAIModelsRefresh)
                    .disabled(isLoadingModels || settings.endpoint.isEmpty || settings.apiKey.isEmpty)
                }
            }

            if let modelLoadError {
                Text(modelLoadError)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.leading, 42)
            } else if !modelOptions.isEmpty {
                Text(String(format: L10n.prefsAIModelsLoaded, modelOptions.count))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private var modelPicker: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(modelOptions, id: \.self) { model in
                    Button {
                        settings.model = model
                        showsModelPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(model)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if model == settings.model {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.preferencesAccent)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            model == settings.model ? palette.selectionBackground : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
        }
        .frame(width: 260, height: min(CGFloat(max(modelOptions.count, 1)) * 34 + 10, 220))
    }

    private var historyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                rowIcon("clock.arrow.circlepath")
                rowText(title: L10n.prefsAIHistoryTitle, subtitle: L10n.prefsAIHistorySubtitle)

                Toggle("", isOn: $settings.chatHistoryEnabled)
                    .labelsHidden()
            }

            if settings.chatHistoryEnabled {
                HStack(spacing: 8) {
                    Button(L10n.prefsAIHistoryOpenFolder) {
                        openHistoryFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer(minLength: 8)

                    Button(L10n.prefsAIHistoryClear) {
                        showsClearHistoryConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(historyStore.conversations.isEmpty)
                }
                .padding(.leading, 42)
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
    }

    private func openHistoryFolder() {
        try? FileManager.default.createDirectory(at: historyStore.storageFolderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([historyStore.storageFolderURL])
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

    private func refreshModels() {
        guard !isLoadingModels else { return }
        modelLoadError = nil
        isLoadingModels = true
        let currentSettings = settings

        Task {
            do {
                let models = try await aiService.fetchModels(settings: currentSettings)
                await MainActor.run {
                    modelOptions = models
                    modelLoadError = models.isEmpty ? L10n.prefsAIModelsEmpty : nil
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    modelLoadError = error.localizedDescription
                    isLoadingModels = false
                }
            }
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct PreferencePanelRowStyle: ViewModifier {
    let palette: ThemePalette

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.surfaceStroke, lineWidth: 1)
            )
    }
}

private struct PreferenceIconButtonLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

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
