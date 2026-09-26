import AppKit
import SwiftUI

@MainActor
final class AppTextActionCoordinator {
    struct Actions {
        let settings: @MainActor () -> AppSettings
        let openAIChat: @MainActor (AIChatInitialInput?) -> Void
    }

    private let translationService: TranslationService
    private let windowCoordinator: AppWindowCoordinator
    private let actions: Actions

    init(
        translationService: TranslationService,
        windowCoordinator: AppWindowCoordinator,
        actions: Actions
    ) {
        self.translationService = translationService
        self.windowCoordinator = windowCoordinator
        self.actions = actions
    }

    func triggerTranslation() {
        // Capture text while the user's app still has Accessibility focus.
        let text = translationService.capture()
        presentTranslationPanel(
            text: text,
            axPermissionDenied: translationService.axPermissionDenied
        )
    }

    func triggerTextActions() {
        let text = translationService.captureWithFallback(promptForPermission: true)
        guard !text.isEmpty else {
            presentTextActionsCaptureError(permissionDenied: translationService.axPermissionDenied)
            return
        }
        presentTextActions(for: text)
    }

    func presentTextActionsHotkeyConflict(keyCode: UInt32, modifiers: UInt32) {
        let shortcut = KeyDisplayFormatter.shortcutLabel(keyCode: keyCode, modifiers: modifiers)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.textActionsHotkeyConflictTitle
        alert.informativeText = String(format: L10n.textActionsHotkeyConflictMessage, shortcut)
        alert.addButton(withTitle: L10n.actionOK)
        alert.runModal()
    }

    func presentTranslationPanel(
        text: String,
        axPermissionDenied: Bool,
        sourceImagePath: String? = nil
    ) {
        let view = AnyView(
            TranslationPanelView(
                sourceText: text,
                axPermissionDenied: axPermissionDenied,
                sourceImagePath: sourceImagePath
            ) { [weak self] in
                self?.hideTranslationPanel()
            }
            .background(Color(nsColor: .windowBackgroundColor))
        )

        // A fresh hosting controller resets TranslationPanelView's @State for each request.
        windowCoordinator.showTranslation(
            contentViewController: NSHostingController(rootView: view),
            size: estimatedTranslationPanelSize(for: text)
        )
    }

    func hideTranslationPanel() {
        windowCoordinator.hideTranslation()
    }

    func hideTextActionsPanel() {
        windowCoordinator.hideTextActions()
    }

    func presentTextActions(for text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            presentTextActionsCaptureError(permissionDenied: false)
            return
        }

        let view = TextActionsPanelView(
            text: normalized,
            theme: actions.settings().theme,
            onAction: { [weak self] action in
                self?.performTextAction(action, text: normalized)
            },
            onDismiss: { [weak self] in
                self?.hideTextActionsPanel()
            }
        )
        windowCoordinator.showTextActions(
            contentViewController: NSHostingController(rootView: view),
            onResign: { [weak self] in
                self?.hideTextActionsPanel()
            }
        )
    }

    private func presentTextActionsCaptureError(permissionDenied: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.textActionsUnavailableTitle
        alert.informativeText = permissionDenied
            ? L10n.textActionsAccessibilityMessage
            : L10n.textActionsNoSelection
        if permissionDenied {
            alert.addButton(withTitle: L10n.translateOpenPrivacy)
            alert.addButton(withTitle: L10n.actionCancel)
            if alert.runModal() == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        } else {
            alert.addButton(withTitle: L10n.actionOK)
            alert.runModal()
        }
    }

    private func performTextAction(_ action: TextAction, text: String) {
        hideTextActionsPanel()
        switch action {
        case .translate:
            presentTranslationPanel(text: text, axPermissionDenied: false)
        case .askAI:
            actions.openAIChat(AIChatInitialInput(text: text))
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func estimatedTranslationPanelSize(for text: String) -> NSSize {
        let width: CGFloat = 560
        let newlineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let wrappedLines = max(0, text.count / 48)
        let estimatedLines = max(1, newlineCount + wrappedLines)
        let estimatedHeight = CGFloat(estimatedLines) * 24 + 250
        return NSSize(width: width, height: min(max(estimatedHeight, 310), 560))
    }
}
