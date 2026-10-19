import AppKit
import MeowAI
import SwiftUI

@MainActor
final class AppAIChatCoordinator {
    struct Actions {
        let showAIPreferences: @MainActor () -> Void
    }

    private let viewModel: LauncherViewModel
    private let historyStore: AIChatHistoryStore
    private let launcherCoordinator: AppLauncherCoordinator
    private let windowCoordinator: AppWindowCoordinator
    private let actions: Actions

    init(
        viewModel: LauncherViewModel,
        historyStore: AIChatHistoryStore,
        launcherCoordinator: AppLauncherCoordinator,
        windowCoordinator: AppWindowCoordinator,
        actions: Actions
    ) {
        self.viewModel = viewModel
        self.historyStore = historyStore
        self.launcherCoordinator = launcherCoordinator
        self.windowCoordinator = windowCoordinator
        self.actions = actions
    }

    func open(_ input: AIChatInitialInput?) {
        guard let input, input.imagePath != nil else {
            show(initialInput: input)
            return
        }
        guard viewModel.settings.ai.supportsVision else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.aiErrorVisionUnsupportedTitle
            alert.informativeText = L10n.aiErrorVisionUnsupported
            alert.addButton(withTitle: L10n.prefsAIModelOpenSettings)
            alert.addButton(withTitle: L10n.actionCancel)
            if alert.runModal() == .alertFirstButtonReturn {
                actions.showAIPreferences()
            }
            return
        }

        let settings = viewModel.settings.ai
        let alert = NSAlert()
        alert.messageText = L10n.aiImagePrivacyTitle
        alert.informativeText = String(
            format: L10n.aiImagePrivacyMessage,
            settings.endpoint,
            settings.imageMaxDimension,
            Int(settings.imageJPEGQuality * 100)
        )
        alert.addButton(withTitle: L10n.aiImagePrivacyConfirm)
        alert.addButton(withTitle: L10n.actionCancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        show(initialInput: persistAttachment(in: input))
    }

    private func show(initialInput: AIChatInitialInput?) {
        let view = AnyView(
            AIChatPanelView(
                viewModel: viewModel,
                initialInput: initialInput,
                historyStore: historyStore,
                onOpenPreferences: actions.showAIPreferences
            )
        )
        launcherCoordinator.hide()
        windowCoordinator.showAIChat(
            contentViewController: NSHostingController(
                rootView: LocalizedRootView { view }
            )
        )
    }

    private func persistAttachment(in input: AIChatInitialInput) -> AIChatInitialInput {
        guard let imagePath = input.imagePath else { return input }
        do {
            let persistedPath = try historyStore.storeAttachment(
                at: URL(fileURLWithPath: imagePath)
            )
            return AIChatInitialInput(text: input.text, imagePath: persistedPath)
        } catch {
            MeowLog.ai.error(
                "Unable to persist AI image attachment: \(error.localizedDescription, privacy: .public)"
            )
            return input
        }
    }
}
