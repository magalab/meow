import AppKit
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

            Button(isRecording ? L10n.prefsHotkeyRecording : hotkeyLabel(keyCode: keyCode, modifiers: modifiers)) {
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

            if isModifierOnlyKey(keyCode) {
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

    private func hotkeyLabel(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined(separator: " ")
    }

    private func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default: return "Key \(keyCode)"
        }
    }

    private func isModifierOnlyKey(_ keyCode: UInt32) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
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
