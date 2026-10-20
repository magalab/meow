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
struct AppLauncherStateTests {
    @Test("Keep Awake state changes update launcher state")
    func keepAwakeStateIsForwardedToLauncher() {
        let suiteName = "AppLauncherStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clipboardStore = ClipboardStore()
        let viewModel = LauncherViewModel(
            settingsStore: SettingsStore(defaults: defaults, aiKeychain: MemoryAIKeychain()),
            discoveryService: AppDiscoveryService(),
            launchHistoryStore: LaunchHistoryStore(defaults: defaults),
            clipboardStore: clipboardStore
        )
        let keepAwakeService = KeepAwakeService()
        let coordinator = AppLauncherCoordinator(
            viewModel: viewModel,
            keepAwakeService: keepAwakeService,
            clipboardStore: clipboardStore,
            windowCoordinator: AppWindowCoordinator()
        )

        coordinator.bindKeepAwakeStateUpdates()
        keepAwakeService.onStateChanged?(.unavailable("test failure"))

        #expect(viewModel.keepAwakeState == .unavailable("test failure"))
    }
}

private final class MemoryAIKeychain: AIKeychainStoring {
    func read() throws -> String? { nil }
    func save(_: String) throws {}
    func delete() throws {}
}
