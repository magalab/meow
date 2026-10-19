@MainActor
final class AppHealthReminderCoordinator {
    struct Actions {
        let isEnabled: @MainActor () -> Bool
        let enable: @MainActor () -> Void
        let startWorking: @MainActor () -> Void
        let pauseOrResume: @MainActor () -> Void
        let startBreak: @MainActor () -> Void
        let skipBreak: @MainActor () -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func handle(_ command: HealthReminderCommand) {
        switch command {
        case .start:
            enableIfNeeded()
            actions.startWorking()
        case .pauseResume:
            guard actions.isEnabled() else {
                actions.enable()
                return
            }
            actions.pauseOrResume()
        case .startBreak:
            enableIfNeeded()
            actions.startBreak()
        case .skipBreak:
            guard actions.isEnabled() else { return }
            actions.skipBreak()
        }
    }

    private func enableIfNeeded() {
        if !actions.isEnabled() {
            actions.enable()
        }
    }
}
