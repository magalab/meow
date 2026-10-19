import MeowAI
import MeowRecording

@MainActor
final class AppLauncherCommandRouter {
    struct Actions {
        let openPreferences: @MainActor () -> Void
        let openAIChat: @MainActor (AIChatInitialInput?) -> Void
        let openAuthenticator: @MainActor () -> Void
        let handleHealthCommand: @MainActor (HealthReminderCommand) -> Void
        let handleScreenshotCommand: @MainActor (ScreenshotCommand) -> Void
        let handleRecordingCommand: @MainActor (RecordingCommand) -> Void
        let handleWhiteboardCommand: @MainActor (WhiteboardCommand) -> Void
        let handleKeepAwakeCommand: @MainActor () -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func bind(to viewModel: LauncherViewModel) {
        viewModel.onOpenPreferences = { [actions] in actions.openPreferences() }
        viewModel.onOpenAIChat = { [actions] in actions.openAIChat($0) }
        viewModel.onOpenAuthenticator = { [actions] in actions.openAuthenticator() }
        viewModel.onHealthCommand = { [actions] in actions.handleHealthCommand($0) }
        viewModel.onScreenshotCommand = { [actions] in actions.handleScreenshotCommand($0) }
        viewModel.onRecordingCommand = { [actions] in actions.handleRecordingCommand($0) }
        viewModel.onWhiteboardCommand = { [actions] in actions.handleWhiteboardCommand($0) }
        viewModel.onKeepAwakeCommand = { [actions] in actions.handleKeepAwakeCommand() }
    }
}
