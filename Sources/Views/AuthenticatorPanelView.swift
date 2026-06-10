import AppKit
import SwiftUI

struct AuthenticatorPanelView: View {
    @ObservedObject var service: AuthenticatorService
    @ObservedObject private var lang = LanguageManager.shared
    @State private var query = ""
    @State private var showingAdd = false
    @State private var tokenToDelete: AuthenticatorToken?
    @State private var errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: service.theme, scheme: colorScheme)
    }

    private var filteredTokens: [AuthenticatorToken] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return service.tokens }
        return service.tokens.filter {
            $0.issuer.localizedCaseInsensitiveContains(search) ||
                $0.account.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if service.tokens.isEmpty {
                emptyState
            } else {
                tokenList
            }
        }
        .frame(width: 370, height: 500)
        .background(
            LinearGradient(
                colors: palette.preferencesGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(isPresented: $showingAdd) {
            AuthenticatorAddView(service: service)
        }
        .alert(L10n.authenticatorDeleteTitle, isPresented: deleteAlertBinding, presenting: tokenToDelete) { token in
            Button(L10n.actionCancel, role: .cancel) {}
            Button(L10n.authenticatorDeleteAction, role: .destructive) {
                do {
                    try service.delete(token)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: { token in
            Text(String(format: L10n.authenticatorDeleteMessage, token.displayName))
        }
        .alert(L10n.authenticatorTitle, isPresented: errorAlertBinding) {
            Button(L10n.authenticatorOK, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .id(lang.refreshToken)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label(L10n.authenticatorTitle, systemImage: AuthenticatorVisuals.symbol)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.preferencesAccent)

                Spacer()

                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help(L10n.authenticatorAddTitle)
            }

            if !service.tokens.isEmpty {
                TextField(L10n.authenticatorSearchPlaceholder, text: $query)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .background(palette.surfaceBackground)
    }

    private var tokenList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredTokens.isEmpty {
                    Text(L10n.authenticatorNoResults)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 56)
                } else {
                    ForEach(filteredTokens) { token in
                        AuthenticatorTokenRow(
                            token: token,
                            service: service,
                            palette: palette,
                            onDelete: { tokenToDelete = token }
                        )
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: AuthenticatorVisuals.emptySymbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(palette.preferencesAccent)
            Text(L10n.authenticatorEmptyTitle)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(L10n.authenticatorEmptySubtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.authenticatorAddTitle) {
                showingAdd = true
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.preferencesAccent)
            Spacer()
        }
        .padding(28)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { tokenToDelete != nil },
            set: { if !$0 { tokenToDelete = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct AuthenticatorTokenRow: View {
    let token: AuthenticatorToken
    @ObservedObject var service: AuthenticatorService
    let palette: ThemePalette
    let onDelete: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = AuthenticatorCodeGenerator.code(for: token, at: context.date) ?? "------"
            let remaining = AuthenticatorCodeGenerator.remainingSeconds(for: token, at: context.date)

            Button {
                service.copyCode(for: token, at: context.date)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(palette.selectionStroke, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(remaining) / CGFloat(token.period))
                            .stroke(palette.preferencesAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(remaining)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(token.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if !token.account.isEmpty {
                            Text(token.account)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(grouped(code))
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundStyle(service.copiedTokenID == token.id ? palette.preferencesAccent : Color.primary)
                }
                .padding(10)
                .background(palette.surfaceBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.surfaceStroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(L10n.authenticatorCopyAction) {
                    service.copyCode(for: token, at: context.date)
                }
                Divider()
                Button(L10n.authenticatorDeleteAction, role: .destructive) {
                    onDelete()
                }
            }
        }
    }

    private func grouped(_ code: String) -> String {
        let midpoint = code.count / 2
        return "\(code.prefix(midpoint)) \(code.suffix(code.count - midpoint))"
    }
}

struct AuthenticatorAddView: View {
    @ObservedObject var service: AuthenticatorService
    @Environment(\.dismiss) private var dismiss
    @State private var otpAuthURL = ""
    @State private var issuer = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var algorithm = AuthenticatorAlgorithm.sha1
    @State private var useURL = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.authenticatorAddTitle)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Picker("", selection: $useURL) {
                Text(L10n.authenticatorAddURLMode).tag(true)
                Text(L10n.authenticatorAddManualMode).tag(false)
            }
            .pickerStyle(.segmented)

            if useURL {
                Text(L10n.authenticatorAddURLHelp)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                SecureField("otpauth://totp/...", text: $otpAuthURL)
                    .textFieldStyle(.roundedBorder)

                Button(L10n.authenticatorPasteAction) {
                    otpAuthURL = NSPasteboard.general.string(forType: .string) ?? ""
                }
                .buttonStyle(.bordered)
            } else {
                Form {
                    TextField(L10n.authenticatorIssuerField, text: $issuer)
                    TextField(L10n.authenticatorAccountField, text: $account)
                    SecureField(L10n.authenticatorSecretField, text: $secret)
                    Picker(L10n.authenticatorAlgorithmField, selection: $algorithm) {
                        ForEach(AuthenticatorAlgorithm.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    Picker(L10n.authenticatorDigitsField, selection: $digits) {
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }
                    TextField(L10n.authenticatorPeriodField, value: $period, format: .number)
                }
                .formStyle(.grouped)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L10n.actionCancel) {
                    dismiss()
                }
                Button(L10n.authenticatorAddAction) {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        do {
            if useURL {
                try service.importOTPAuth(otpAuthURL)
            } else {
                try service.add(
                    issuer: issuer,
                    account: account,
                    secret: secret,
                    digits: digits,
                    period: period,
                    algorithm: algorithm
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
