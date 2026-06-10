import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum AuthenticatorPreferencePage: String, CaseIterable, Identifiable {
    case overview
    case importTokens
    case sync

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .overview: return L10n.prefsAuthenticatorPageOverview
        case .importTokens: return L10n.prefsAuthenticatorPageImport
        case .sync: return L10n.prefsAuthenticatorPageSync
        }
    }
}

struct AuthenticatorPreferencesView: View {
    let theme: AppTheme
    @ObservedObject var service: AuthenticatorService
    @Binding var enabled: Bool
    @Binding var iCloudSyncEnabled: Bool

    @State private var selectedPage = AuthenticatorPreferencePage.overview
    @State private var showingAddAccount = false
    @State private var importValue = ""
    @State private var importMessage: String?
    @State private var importSucceeded = false
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedPage) {
                ForEach(AuthenticatorPreferencePage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .pickerStyle(.segmented)

            switch selectedPage {
            case .overview:
                overviewPage
            case .importTokens:
                importPage
            case .sync:
                syncPage
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AuthenticatorAddView(service: service)
        }
    }

    private var overviewPage: some View {
        VStack(spacing: 10) {
            PreferenceToggleRow(
                title: L10n.prefsAuthenticatorEnabledTitle,
                subtitle: L10n.prefsAuthenticatorEnabledSubtitle,
                symbol: AuthenticatorVisuals.symbol,
                theme: theme,
                isOn: $enabled
            )

            PreferenceInfoRow(
                title: L10n.prefsAuthenticatorSecurityTitle,
                subtitle: L10n.prefsAuthenticatorSecuritySubtitle,
                symbol: "lock.shield",
                theme: theme
            )

            if enabled {
                PreferenceInfoRow(
                    title: L10n.prefsAuthenticatorAccountsTitle,
                    subtitle: String(format: L10n.prefsAuthenticatorAccountsCount, service.tokens.count),
                    symbol: "person.crop.square.filled.and.at.rectangle",
                    theme: theme
                )

                HStack(spacing: 10) {
                    actionButton(
                        L10n.authenticatorAddTitle,
                        symbol: "plus.circle.fill",
                        action: { showingAddAccount = true }
                    )
                    actionButton(
                        L10n.prefsAuthenticatorOpen,
                        symbol: "rectangle.portrait.and.arrow.right",
                        action: service.showPanel
                    )
                }
            }
        }
    }

    private var importPage: some View {
        VStack(spacing: 10) {
            PreferenceInfoRow(
                title: L10n.prefsAuthenticatorImportTitle,
                subtitle: L10n.prefsAuthenticatorImportSubtitle,
                symbol: "square.and.arrow.down",
                theme: theme
            )

            if enabled {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("otpauth://totp/...", text: $importValue)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(L10n.authenticatorPasteAction) {
                            importValue = NSPasteboard.general.string(forType: .string) ?? ""
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(L10n.prefsAuthenticatorImportAction) {
                            importToken()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.preferencesAccent)
                    }

                    if let importMessage {
                        Label(
                            importMessage,
                            systemImage: importSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(importSucceeded ? palette.preferencesAccent : Color.red)
                    }
                }
                .padding(12)
                .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.surfaceStroke, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.prefsAuthenticatorJSONTitle, systemImage: "doc.text")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    Text(L10n.prefsAuthenticatorJSONSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            importJSONFile()
                        } label: {
                            Label(L10n.prefsAuthenticatorJSONImport, systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            exportJSONFile()
                        } label: {
                            Label(L10n.prefsAuthenticatorJSONExport, systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(service.tokens.isEmpty)
                    }
                }
                .padding(12)
                .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.surfaceStroke, lineWidth: 1)
                )
            } else {
                disabledNotice
            }
        }
    }

    private var syncPage: some View {
        VStack(spacing: 10) {
            if enabled {
                PreferenceToggleRow(
                    title: L10n.prefsAuthenticatorICloudTitle,
                    subtitle: L10n.prefsAuthenticatorICloudSubtitle,
                    symbol: "icloud",
                    theme: theme,
                    isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in
                            if service.requestICloudSyncEnabled(newValue) {
                                iCloudSyncEnabled = newValue
                            } else {
                                iCloudSyncEnabled = false
                            }
                        }
                    )
                )

                PreferenceInfoRow(
                    title: syncStatusTitle,
                    subtitle: syncStatusSubtitle,
                    symbol: syncStatusSymbol,
                    theme: theme
                )

                if service.isICloudSyncEnabled {
                    Button {
                        do {
                            try service.refreshFromICloud()
                        } catch {}
                    } label: {
                        Label(L10n.prefsAuthenticatorSyncNow, systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                PreferenceInfoRow(
                    title: L10n.prefsAuthenticatorSyncDevelopmentTitle,
                    subtitle: L10n.prefsAuthenticatorSyncDevelopmentSubtitle,
                    symbol: "hammer",
                    theme: theme
                )
            } else {
                disabledNotice
            }
        }
    }

    private var syncStatusTitle: String {
        switch service.syncState {
        case .disabled:
            return L10n.prefsAuthenticatorSyncDisabledStatus
        case .checking:
            return L10n.prefsAuthenticatorSyncChecking
        case .ready:
            return L10n.prefsAuthenticatorSyncReady
        case .unavailable:
            return L10n.prefsAuthenticatorSyncUnavailable
        }
    }

    private var syncStatusSubtitle: String {
        switch service.syncState {
        case .disabled:
            return L10n.prefsAuthenticatorSyncDisabledSubtitle
        case .checking:
            return L10n.prefsAuthenticatorSyncCheckingSubtitle
        case .ready:
            if let lastSyncAt = service.lastSyncAt {
                return String(
                    format: L10n.prefsAuthenticatorSyncLastUpdated,
                    lastSyncAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
            return L10n.prefsAuthenticatorSyncReadySubtitle
        case let .unavailable(message):
            return message
        }
    }

    private var syncStatusSymbol: String {
        switch service.syncState {
        case .disabled:
            return "icloud.slash"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.icloud"
        case .unavailable:
            return "exclamationmark.icloud"
        }
    }

    private var disabledNotice: some View {
        PreferenceInfoRow(
            title: L10n.prefsAuthenticatorDisabledTitle,
            subtitle: L10n.prefsAuthenticatorDisabledSubtitle,
            symbol: "power",
            theme: theme
        )
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.preferencesAccent)
    }

    private func importToken() {
        do {
            try service.importOTPAuth(importValue)
            importValue = ""
            importSucceeded = true
            importMessage = L10n.prefsAuthenticatorImportSuccess
        } catch {
            importSucceeded = false
            importMessage = error.localizedDescription
        }
    }

    private func importJSONFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let result = try service.importJSON(Data(contentsOf: url))
            importSucceeded = true
            importMessage = String(
                format: L10n.prefsAuthenticatorJSONImportResult,
                result.imported,
                result.duplicates
            )
        } catch {
            importSucceeded = false
            importMessage = error.localizedDescription
        }
    }

    private func exportJSONFile() {
        let warning = NSAlert()
        warning.alertStyle = .warning
        warning.messageText = L10n.prefsAuthenticatorJSONExportWarningTitle
        warning.informativeText = L10n.prefsAuthenticatorJSONExportWarningMessage
        warning.addButton(withTitle: L10n.prefsAuthenticatorJSONExportConfirm)
        warning.addButton(withTitle: L10n.actionCancel)
        guard warning.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MeowAuthenticatorBackup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try service.exportJSON().write(to: url, options: .atomic)
            importSucceeded = true
            importMessage = L10n.prefsAuthenticatorJSONExportSuccess
        } catch {
            importSucceeded = false
            importMessage = error.localizedDescription
        }
    }
}
