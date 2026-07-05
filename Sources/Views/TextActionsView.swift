import SwiftUI

enum TextActionsVisuals {
    static let symbol = "text.badge.star"
}

enum TextAction: Hashable, Sendable {
    case translate
    case askAI
    #if MEOW_VOICE
    case speak
    #endif

    static func available(canSpeak: Bool) -> [TextAction] {
        var actions: [TextAction] = [.translate, .askAI]
        #if MEOW_VOICE
        if canSpeak {
            actions.append(.speak)
        }
        #endif
        return actions
    }

    var title: String {
        switch self {
        case .translate: return L10n.textActionsTranslate
        case .askAI: return L10n.textActionsAskAI
        #if MEOW_VOICE
        case .speak: return L10n.textActionsSpeak
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .translate: return "translate"
        case .askAI: return "sparkles"
        #if MEOW_VOICE
        case .speak: return "speaker.wave.2.fill"
        #endif
        }
    }
}

struct TextActionsPanelView: View {
    let text: String
    let theme: AppTheme
    let canSpeak: Bool
    let onAction: (TextAction) -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        MeowTheme.palette(theme: theme, scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            textPreview
            Divider()
            actions
        }
        .frame(width: 520, height: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: TextActionsVisuals.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.preferencesAccent)
                .frame(width: 30, height: 30)
                .background(palette.iconChipBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(L10n.textActionsTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.actionCancel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.textActionsSelection)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            ForEach(TextAction.available(canSpeak: canSpeak), id: \.self) { action in
                actionButton(
                    title: action.title,
                    symbol: action.symbol,
                    action: action
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func actionButton(title: String, symbol: String, action: TextAction) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(palette.preferencesAccent)
    }
}
