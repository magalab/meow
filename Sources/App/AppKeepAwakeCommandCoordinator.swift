@MainActor
final class AppKeepAwakeCommandCoordinator {
    struct Actions {
        let hideLauncher: @MainActor () -> Void
        let toggleKeepAwake: @MainActor () async throws -> Void
        let presentError: @MainActor (Error) -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func handleCommand() {
        actions.hideLauncher()
        Task { @MainActor [weak self] in
            await self?.toggleKeepAwake()
        }
    }

    func toggleKeepAwake() async {
        do {
            try await actions.toggleKeepAwake()
        } catch is CancellationError {
            // A user stop or replacement can cancel an in-flight start.
        } catch {
            actions.presentError(error)
        }
    }
}
