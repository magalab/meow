import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardPreferencesView: View {
    @Binding var settings: AppSettings
    @ObservedObject var store: ClipboardStore
    let theme: AppTheme

    @State private var showingClearConfirmation = false
    @State private var exclusionError: String?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsClipboardTitle,
                subtitle: L10n.prefsClipboardSubtitle,
                symbol: "clipboard",
                theme: theme,
                isOn: $settings.clipboardHistoryEnabled
            )

            if settings.clipboardHistoryEnabled {
                PreferenceToggleRow(
                    title: L10n.prefsClipboardImagePreviewTitle,
                    subtitle: L10n.prefsClipboardImagePreviewSubtitle,
                    symbol: "photo.on.rectangle",
                    theme: theme,
                    isOn: $settings.clipboardShowImagePreviews
                )

                pickerRow(
                    title: L10n.prefsClipboardRetentionTitle,
                    subtitle: L10n.prefsClipboardRetentionSubtitle,
                    symbol: "calendar.badge.clock"
                ) {
                    Picker("", selection: $settings.clipboardRetention) {
                        ForEach(ClipboardRetention.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                pickerRow(
                    title: L10n.prefsClipboardStorageLimitTitle,
                    subtitle: L10n.prefsClipboardStorageLimitSubtitle,
                    symbol: "externaldrive"
                ) {
                    Picker("", selection: $settings.clipboardImageStorageLimitMB) {
                        ForEach([128, 256, 512, 1024, 2048], id: \.self) { value in
                            Text(ByteCountFormatter.string(
                                fromByteCount: Int64(value) * 1_024 * 1_024,
                                countStyle: .file
                            )).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                excludedApplications
                storageActions
            }
        }
        .animation(.snappy(duration: 0.2), value: settings.clipboardHistoryEnabled)
        .alert(L10n.clipboardClearAllTitle, isPresented: $showingClearConfirmation) {
            Button(L10n.actionCancel, role: .cancel) {}
            Button(L10n.clipboardClearAll, role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text(L10n.clipboardClearAllMessage)
        }
        .alert(
            L10n.prefsClipboardExcludedAppErrorTitle,
            isPresented: Binding(
                get: { exclusionError != nil },
                set: { if !$0 { exclusionError = nil } }
            )
        ) {
            Button(L10n.actionOK) { exclusionError = nil }
        } message: {
            Text(exclusionError ?? "")
        }
    }

    private var excludedApplications: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                preferenceIcon("hand.raised")
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.prefsClipboardExcludedAppsTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(L10n.prefsClipboardExcludedAppsSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.prefsClipboardExcludedAppsAdd) {
                    chooseExcludedApplication()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if !settings.clipboardDisabledAppBundleIDs.isEmpty {
                Divider().padding(.leading, 52)
                ForEach(settings.clipboardDisabledAppBundleIDs, id: \.self) { bundleID in
                    HStack(spacing: 10) {
                        appIcon(bundleID: bundleID)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(appName(bundleID: bundleID))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(bundleID)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            settings.clipboardDisabledAppBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.prefsClipboardExcludedAppsRemove)
                    }
                    .padding(.leading, 52)
                    .padding(.trailing, 12)
                    .padding(.vertical, 7)
                }
            }
        }
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private var storageActions: some View {
        HStack(spacing: 12) {
            preferenceIcon("internaldrive")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.prefsClipboardStorageTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(
                    String(
                        format: L10n.prefsClipboardStorageSubtitle,
                        ByteCountFormatter.string(
                            fromByteCount: store.storageUsageBytes,
                            countStyle: .file
                        )
                    )
                )
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.prefsClipboardOpenFolder) {
                try? FileManager.default.createDirectory(
                    at: store.storageDirectoryURL,
                    withIntermediateDirectories: true
                )
                NSWorkspace.shared.activateFileViewerSelecting([store.storageDirectoryURL])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(L10n.clipboardClearAll, role: .destructive) {
                showingClearConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private func pickerRow<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            preferenceIcon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        )
    }

    private func preferenceIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.preferencesAccent)
            .frame(width: 30, height: 30)
            .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.prefsClipboardExcludedAppsPickerTitle
        panel.prompt = L10n.actionChoose
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier
        else { return }

        guard !settings.clipboardDisabledAppBundleIDs.contains(bundleID) else {
            exclusionError = L10n.prefsClipboardExcludedAppDuplicate
            return
        }
        settings.clipboardDisabledAppBundleIDs.append(bundleID)
    }

    private func appName(bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    @ViewBuilder
    private func appIcon(bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
        }
    }
}
