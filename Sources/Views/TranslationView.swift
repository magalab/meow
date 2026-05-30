import SwiftUI
import NaturalLanguage
@preconcurrency import Translation

// MARK: - Public panel view

/// Top-level SwiftUI view for the floating translation panel.
struct TranslationPanelView: View {
    private let panelWidth: CGFloat = 560

    let sourceText: String
    /// Set true when capture() found that AX permission is missing.
    var axPermissionDenied: Bool = false
    let onDismiss: () -> Void

    var body: some View {
        if axPermissionDenied && sourceText.isEmpty {
            noPermissionView
        } else if sourceText.isEmpty {
            noSelectionView
        } else {
            TranslationContentView(sourceText: sourceText, onDismiss: onDismiss)
        }
    }

    private var noPermissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(L10n.translateNeedAccessibility)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button(L10n.translateOpenPrivacy) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(L10n.translateDismiss) { onDismiss() }
                    .controlSize(.small)
            }
        }
        .padding(32)
        .frame(width: panelWidth)
    }

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(L10n.translateNoSelection)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L10n.translateDismiss) { onDismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(32)
        .frame(width: panelWidth)
    }
}


// MARK: - Translation view

private struct TranslationContentView: View {
    private let panelWidth: CGFloat = 560

    let sourceText: String
    let onDismiss: () -> Void

    @State private var translatedText: String = ""
    @State private var isTranslating = true
    @State private var errorMessage: String?
    // Start nil — set onAppear so the task fires exactly once per view lifetime.
    @State private var config: TranslationSession.Configuration? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            sourceSection
            Divider()
            translationSection
        }
        .frame(width: panelWidth)
        .onAppear {
            config = makeConfiguration(for: sourceText)
        }
        .translationTask(config) { session in
            isTranslating = true
            errorMessage = nil
            translatedText = ""
            do {
                let response = try await session.translate(sourceText)
                translatedText = response.targetText
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranslating = false
        }
    }

    private func makeConfiguration(for text: String) -> TranslationSession.Configuration {
        let sourceIdentifier = detectLanguageIdentifier(for: text)
        let targetIdentifier = preferredTargetIdentifier(sourceIdentifier: sourceIdentifier)

        // Never leave source nil, otherwise Translation may show a language picker.
        let source = Locale.Language(
            identifier: sourceIdentifier ?? fallbackSourceIdentifier(forTargetIdentifier: targetIdentifier)
        )
        let target = Locale.Language(identifier: targetIdentifier)
        return TranslationSession.Configuration(source: source, target: target)
    }

    private func detectLanguageIdentifier(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        let id = lang.rawValue.lowercased()
        if id.hasPrefix("zh") {
            return "zh-Hans"
        }
        if id.hasPrefix("en") {
            return "en"
        }
        // Fast heuristic for mixed/short text where NL may return nil/und.
        if text.contains(where: { $0.isASCII && $0.isLetter }) {
            return "en"
        }
        if text.unicodeScalars.contains(where: { scalar in
            (0x4E00 ... 0x9FFF).contains(scalar.value)
        }) {
            return "zh-Hans"
        }
        return nil
    }

    private func preferredTargetIdentifier(sourceIdentifier: String?) -> String {
        let systemPreferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        var target = systemPreferred.hasPrefix("zh") ? "zh-Hans" : "en"

        guard let sourceIdentifier else { return target }
        let source = sourceIdentifier.lowercased()

        // If source and target are the same family, flip to the opposite language.
        if source.hasPrefix("zh"), target.lowercased().hasPrefix("zh") {
            target = "en"
        } else if source.hasPrefix("en"), target.lowercased().hasPrefix("en") {
            target = "zh-Hans"
        }

        return target
    }

    private func fallbackSourceIdentifier(forTargetIdentifier targetIdentifier: String) -> String {
        targetIdentifier.lowercased().hasPrefix("zh") ? "en" : "zh-Hans"
    }

    // MARK: Sub-views

    private var header: some View {
        HStack {
            Label(L10n.translateTitle, systemImage: "translate")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sourceSection: some View {
        ScrollView {
            Text(sourceText)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
            .frame(minHeight: sourceSectionHeight, maxHeight: sourceSectionHeight)
    }

    private var translationSection: some View {
        Group {
            if isTranslating {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.75)
                    Text(L10n.translateTranslating)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    Text(translatedText)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .frame(minHeight: translationSectionHeight, maxHeight: translationSectionHeight)
            }
        }
    }

    private var sourceSectionHeight: CGFloat {
        estimatedSectionHeight(for: sourceText, minHeight: 96, maxHeight: 210)
    }

    private var translationSectionHeight: CGFloat {
        if translatedText.isEmpty {
            return max(110, sourceSectionHeight - 8)
        }
        return estimatedSectionHeight(for: translatedText, minHeight: 110, maxHeight: 220)
    }

    private func estimatedSectionHeight(for text: String, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let newlineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let wrappedLines = max(0, text.count / 48)
        let lines = max(1, newlineCount + wrappedLines)
        let estimated = CGFloat(lines) * 22 + 26
        return min(max(estimated, minHeight), maxHeight)
    }
}
