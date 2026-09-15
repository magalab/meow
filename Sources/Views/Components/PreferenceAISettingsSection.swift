import AppKit
@preconcurrency import ApplicationServices
import Carbon
import SwiftUI

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
            visionRow
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

    private var visionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                rowIcon("photo.badge.checkmark")
                rowText(
                    title: L10n.prefsAIVisionTitle,
                    subtitle: L10n.prefsAIVisionSubtitle
                )
                Toggle("", isOn: $settings.supportsVision)
                    .labelsHidden()
            }

            if settings.supportsVision {
                HStack(spacing: 12) {
                    Text(L10n.prefsAIImageMaxDimension)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.imageMaxDimension) {
                        ForEach([1024, 1600, 2048, 3072], id: \.self) { dimension in
                            Text("\(dimension) px").tag(dimension)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)

                    Text(L10n.prefsAIImageQuality)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Slider(value: $settings.imageJPEGQuality, in: 0.4...1, step: 0.05)
                        .frame(width: 110)
                    Text("\(Int(settings.imageJPEGQuality * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.leading, 42)

                Text(L10n.prefsAIVisionPrivacy)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 42)
            }
        }
        .modifier(PreferencePanelRowStyle(palette: palette))
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
