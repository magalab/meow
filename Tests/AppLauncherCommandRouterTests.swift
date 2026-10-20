import Foundation
import MeowAI
import MeowClipboard
import MeowLauncher
import Testing
#if MEOW_VOICE
@testable import Miao
#else
@testable import Meow
#endif

@MainActor
struct AppLauncherCommandRouterTests {
    @Test
    func launcherFeatureCommandsAreForwardedToTheirOwners() {
        let suiteName = "AppLauncherCommandRouterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let viewModel = LauncherViewModel(
            settingsStore: SettingsStore(defaults: defaults, aiKeychain: MemoryAIKeychain()),
            discoveryService: AppDiscoveryService(),
            launchHistoryStore: LaunchHistoryStore(defaults: defaults),
            clipboardStore: ClipboardStore()
        )
        var events: [String] = []
        let router = AppLauncherCommandRouter(actions: .init(
            openPreferences: { events.append("preferences") },
            openAIChat: { _ in events.append("ai") },
            openAuthenticator: { events.append("authenticator") },
            handleHealthCommand: { _ in events.append("health") },
            handleScreenshotCommand: { _ in events.append("screenshot") },
            handleRecordingCommand: { _ in events.append("recording") },
            handleWhiteboardCommand: { _ in events.append("whiteboard") },
            handleKeepAwakeCommand: { events.append("keep-awake") }
        ))

        router.bind(to: viewModel)
        viewModel.onOpenPreferences?()
        viewModel.onOpenAIChat?(nil)
        viewModel.onOpenAuthenticator?()
        viewModel.onHealthCommand?(.startBreak)
        viewModel.onScreenshotCommand?(.openHistory)
        viewModel.onRecordingCommand?(.pauseResume)
        viewModel.onWhiteboardCommand?(.toggleEditing)
        viewModel.onKeepAwakeCommand?()

        #expect(events == [
            "preferences", "ai", "authenticator", "health", "screenshot", "recording", "whiteboard", "keep-awake",
        ])
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class MemoryAIKeychain: AIKeychainStoring {
    func read() throws -> String? { nil }
    func save(_: String) throws {}
    func delete() throws {}
}
